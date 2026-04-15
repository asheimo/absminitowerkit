/*
 * moodlight.c
 *
 * Temperature-reactive LED controller for GeeekPi ABS Minitower.
 * Reads CPU temperature and maps it to a colour gradient:
 *
 *   <= 40°C  cool blue
 *      50°C  cyan
 *      60°C  green
 *      70°C  yellow
 *      80°C  orange
 *   >= 85°C  red
 *
 * Builds against the rpi_ws281x library (ws2811.h / libws2811).
 * Hardware: 8 LEDs on GPIO 18, GBR strip type, DMA channel 10.
 *
 * Usage:
 *   moodlight [-g <gpio>] [-d <dma>] [-n <led_count>] [-b <brightness>] [-c] [-h]
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <getopt.h>

#include "ws2811.h"

/* --------------------------------------------------------------------------
 * Defaults
 * -------------------------------------------------------------------------- */
#define DEFAULT_GPIO        18
#define DEFAULT_DMA         10
#define DEFAULT_LED_COUNT   8
#define DEFAULT_BRIGHTNESS  255
#define STRIP_TYPE          WS2811_STRIP_GBR

#define TEMP_PATH           "/sys/class/thermal/thermal_zone0/temp"
#define UPDATE_INTERVAL_US  (500 * 1000)   /* 0.5 seconds */

/* --------------------------------------------------------------------------
 * Temperature thresholds (°C) and corresponding RGB colours
 * -------------------------------------------------------------------------- */
typedef struct {
    float temp;
    uint8_t r, g, b;
} temp_color_t;

static const temp_color_t TEMP_COLORS[] = {
    { 40.0f, 0x00, 0x00, 0xFF },   /* cool blue  */
    { 50.0f, 0x00, 0xFF, 0xFF },   /* cyan       */
    { 60.0f, 0x00, 0xFF, 0x00 },   /* green      */
    { 70.0f, 0xFF, 0xFF, 0x00 },   /* yellow     */
    { 80.0f, 0xFF, 0x80, 0x00 },   /* orange     */
    { 85.0f, 0xFF, 0x00, 0x00 },   /* red        */
};
#define NUM_TEMP_COLORS  (int)(sizeof(TEMP_COLORS) / sizeof(TEMP_COLORS[0]))

/* --------------------------------------------------------------------------
 * Globals
 * -------------------------------------------------------------------------- */
static volatile int running = 1;
static int clear_on_exit    = 0;

static ws2811_t ledstring = {
    .freq   = WS2811_TARGET_FREQ,
    .dmanum = DEFAULT_DMA,
    .channel = {
        [0] = {
            .gpionum    = DEFAULT_GPIO,
            .invert     = 0,
            .count      = DEFAULT_LED_COUNT,
            .strip_type = STRIP_TYPE,
            .brightness = DEFAULT_BRIGHTNESS,
        },
        [1] = { .gpionum = 0, .invert = 0, .count = 0, .brightness = 0 },
    },
};

/* --------------------------------------------------------------------------
 * Signal handler
 * -------------------------------------------------------------------------- */
static void handle_signal(int signum)
{
    (void)signum;
    running = 0;
}

/* --------------------------------------------------------------------------
 * Read CPU temperature in degrees Celsius
 * Returns -1.0 on failure.
 * -------------------------------------------------------------------------- */
static float read_cpu_temp(void)
{
    FILE *f = fopen(TEMP_PATH, "r");
    if (!f) return -1.0f;

    int raw = 0;
    int ok  = fscanf(f, "%d", &raw);
    fclose(f);

    return (ok == 1) ? (raw / 1000.0f) : -1.0f;
}

/* --------------------------------------------------------------------------
 * Linearly interpolate between two uint8_t values
 * -------------------------------------------------------------------------- */
static uint8_t lerp_u8(uint8_t a, uint8_t b, float t)
{
    return (uint8_t)(a + (int)((b - a) * t));
}

/* --------------------------------------------------------------------------
 * Map a temperature to a GBR colour word (as expected by STRIP_TYPE GBR)
 * -------------------------------------------------------------------------- */
static ws2811_led_t temp_to_color(float temp)
{
    /* Clamp to range */
    if (temp <= TEMP_COLORS[0].temp) {
        uint8_t r = TEMP_COLORS[0].r;
        uint8_t g = TEMP_COLORS[0].g;
        uint8_t b = TEMP_COLORS[0].b;
        return (ws2811_led_t)((g << 16) | (b << 8) | r);
    }
    if (temp >= TEMP_COLORS[NUM_TEMP_COLORS - 1].temp) {
        uint8_t r = TEMP_COLORS[NUM_TEMP_COLORS - 1].r;
        uint8_t g = TEMP_COLORS[NUM_TEMP_COLORS - 1].g;
        uint8_t b = TEMP_COLORS[NUM_TEMP_COLORS - 1].b;
        return (ws2811_led_t)((g << 16) | (b << 8) | r);
    }

    /* Find surrounding segments and interpolate */
    for (int i = 0; i < NUM_TEMP_COLORS - 1; i++) {
        if (temp >= TEMP_COLORS[i].temp && temp < TEMP_COLORS[i + 1].temp) {
            float t = (temp - TEMP_COLORS[i].temp) /
                      (TEMP_COLORS[i + 1].temp - TEMP_COLORS[i].temp);

            uint8_t r = lerp_u8(TEMP_COLORS[i].r, TEMP_COLORS[i + 1].r, t);
            uint8_t g = lerp_u8(TEMP_COLORS[i].g, TEMP_COLORS[i + 1].g, t);
            uint8_t b = lerp_u8(TEMP_COLORS[i].b, TEMP_COLORS[i + 1].b, t);

            /* GBR packing: bits 23-16 = G, bits 15-8 = B, bits 7-0 = R */
            return (ws2811_led_t)((g << 16) | (b << 8) | r);
        }
    }

    return 0;
}

/* --------------------------------------------------------------------------
 * Set all LEDs to the same colour and render
 * -------------------------------------------------------------------------- */
static ws2811_return_t set_all_leds(ws2811_led_t color)
{
    int count = ledstring.channel[0].count;
    for (int i = 0; i < count; i++) {
        ledstring.channel[0].leds[i] = color;
    }
    return ws2811_render(&ledstring);
}

/* --------------------------------------------------------------------------
 * Argument parsing
 * -------------------------------------------------------------------------- */
static void parse_args(int argc, char **argv)
{
    static struct option longopts[] = {
        { "help",       no_argument,       0, 'h' },
        { "gpio",       required_argument, 0, 'g' },
        { "dma",        required_argument, 0, 'd' },
        { "leds",       required_argument, 0, 'n' },
        { "brightness", required_argument, 0, 'b' },
        { "clear",      no_argument,       0, 'c' },
        { 0, 0, 0, 0 }
    };

    int c;
    while ((c = getopt_long(argc, argv, "hg:d:n:b:c", longopts, NULL)) != -1) {
        switch (c) {
        case 'h':
            printf(
                "moodlight - temperature-reactive LED controller\n\n"
                "Usage: moodlight [options]\n\n"
                "  -g, --gpio <pin>         GPIO pin (default: %d)\n"
                "  -d, --dma <channel>      DMA channel (default: %d)\n"
                "  -n, --leds <count>       Number of LEDs (default: %d)\n"
                "  -b, --brightness <0-255> LED brightness (default: %d)\n"
                "  -c, --clear              Clear LEDs on exit\n"
                "  -h, --help               This help text\n\n"
                "Colour mapping:\n"
                "  <=40C  blue\n"
                "    50C  cyan\n"
                "    60C  green\n"
                "    70C  yellow\n"
                "    80C  orange\n"
                "  >=85C  red\n",
                DEFAULT_GPIO, DEFAULT_DMA, DEFAULT_LED_COUNT, DEFAULT_BRIGHTNESS
            );
            exit(0);

        case 'g':
            ledstring.channel[0].gpionum = atoi(optarg);
            break;

        case 'd':
            ledstring.dmanum = atoi(optarg);
            break;

        case 'n': {
            int n = atoi(optarg);
            if (n > 0) ledstring.channel[0].count = n;
            break;
        }

        case 'b': {
            int b = atoi(optarg);
            if (b >= 0 && b <= 255)
                ledstring.channel[0].brightness = (uint8_t)b;
            break;
        }

        case 'c':
            clear_on_exit = 1;
            break;

        default:
            fprintf(stderr, "Unknown option. Use -h for help.\n");
            exit(1);
        }
    }
}

/* --------------------------------------------------------------------------
 * main
 * -------------------------------------------------------------------------- */
int main(int argc, char **argv)
{
    ws2811_return_t ret;

    parse_args(argc, argv);

    signal(SIGINT,  handle_signal);
    signal(SIGTERM, handle_signal);

    if ((ret = ws2811_init(&ledstring)) != WS2811_SUCCESS) {
        fprintf(stderr, "ws2811_init failed: %s\n", ws2811_get_return_t_str(ret));
        return ret;
    }

    while (running) {
        float temp = read_cpu_temp();

        if (temp < 0.0f) {
            fprintf(stderr, "Warning: could not read CPU temperature, retrying...\n");
        } else {
            ws2811_led_t color = temp_to_color(temp);
            if ((ret = set_all_leds(color)) != WS2811_SUCCESS) {
                fprintf(stderr, "ws2811_render failed: %s\n", ws2811_get_return_t_str(ret));
                break;
            }
        }

        usleep(UPDATE_INTERVAL_US);
    }

    if (clear_on_exit) {
        set_all_leds(0);
    }

    ws2811_fini(&ledstring);
    return (int)ret;
}
