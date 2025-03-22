const uart = @import("../uart.zig");
const util = @import("../util.zig");
const fmt = @import("../fmt.zig");
const interrupts = @import("../interrupts/interrupt.zig");
const timer_interrupts = @import("../interrupts/timer-interrupts.zig");
const timer = @import("../timer.zig");
const gpio = @import("../gpio.zig");

const LED_PIN = 17;
var on: bool = false;
var led_timer_id: u32 = 0;
var done: bool = false;

fn blink_led() void {
    uart.puts("LED toggle\n");
    if (on) {
        gpio.set_off(LED_PIN);
    } else {
        gpio.set_on(LED_PIN);
    }
    on = !on;
}

fn cancel_led() void {
    uart.puts("One-time task executed!\n");
    _ = timer_interrupts.cancel_timer(led_timer_id);
    done = true;
}

pub fn run_example() void {
    timer_interrupts.init();
    gpio.set_output(LED_PIN);

    // Create a periodic timer that blinks an LED every 500ms
    led_timer_id = timer_interrupts.add_timer(250, 250, blink_led);

    // Do something and wait for 5 seconds to turn timer off
    uart.puts("Starting 5000s delay...\n");
    _ = timer_interrupts.add_timer(5000, 0, cancel_led);

    // wait until all timers are done
    while (!done) {}

    interrupts.disable_interrupts();

    uart.puts("Done with timers..!\n");
}
