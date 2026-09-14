# Ambient Light and Presence Lighting Blueprint Design

## Purpose

Create a reusable Home Assistant automation blueprint that turns lighting on when it is dark and someone is home, and fades it off once the environment is bright. The blueprint must recover from missed threshold crossings, require no helper entities, and allow users to supply any Home Assistant action sequence for the on and off behavior.

The initial use case uses a sensor that reads approximately 193 at midday and 4100 in the middle of the night. Its default dark threshold is 2800 and its default bright threshold is 500.

## Location and Ownership

- Repository: `RustedAperture/ha_blueprints`
- Proposed blueprint: `blueprints/automation/ambient_light_presence/ambient_light_presence.yaml`
- Blueprint author credit: RustedAperture
- Domain: Home Assistant automation blueprint

This is a new blueprint derived from RustedAperture's Home Assistant automation requirements. Ashley's Light Fader is supported as an optional user-selected action but is not a blueprint dependency.

## Inputs

The blueprint exposes these inputs in the Home Assistant blueprint UI:

1. **Ambient sensor**: one numeric sensor entity.
2. **Higher values mean darker**: a boolean, enabled by default. Disabling it reverses both threshold comparisons for sensors whose values decrease as it gets darker.
3. **Dark threshold**: a number, default `2800`.
4. **Bright threshold**: a number, default `500`.
5. **Dark hold time**: a duration, default 5 minutes.
6. **Bright hold time**: a duration, default 5 minutes.
7. **People**: one or more `person` entities. At least one selected person must be home before the on action may run.
8. **Awake start time**: a time, default `07:00:00`.
9. **Awake end time**: a time, default `23:00:00`.
10. **Monitored light**: one light entity or light group used to prevent unnecessary repeated actions.
11. **Turn-on action**: an arbitrary Home Assistant action sequence.
12. **Turn-off action**: an arbitrary Home Assistant action sequence.

The threshold descriptions will explain that the dark threshold must be farther toward the sensor's dark end than the bright threshold. This gap provides hysteresis and prevents rapid cycling.

The action descriptions will include Ashley's Light Fader guidance: a typical on action can fade to 50 percent over 30 minutes, and an off action can use `endBrightnessPercent: 0`.

## Trigger and Decision Flow

### Turn-on candidates

The blueprint evaluates the turn-on action after any of these events:

- The ambient sensor remains beyond the dark threshold for the configured dark hold time.
- Any selected person changes to `home`.
- The configured awake start time occurs.
- Home Assistant starts. The blueprint waits 30 seconds for entity states to settle before evaluating conditions.

All turn-on candidates use the same final checks:

- The ambient sensor currently satisfies the dark comparison.
- At least one selected person is currently `home`.
- The current local time is within the configured awake window.
- The monitored light is currently `off`.

This re-evaluation handles cases where the original threshold crossing happened while everyone was away or asleep. Manually turning the monitored light off does not trigger the automation, so the blueprint respects manual control until another qualifying event occurs.

### Turn-off candidate

The turn-off action is evaluated when the ambient sensor remains beyond the bright threshold for the configured bright hold time.

It runs only when the monitored light is currently `on`. Presence and awake-time restrictions do not apply to the off path. The blueprint does not turn lighting off merely because the awake window ends.

### Sensor direction

When **Higher values mean darker** is enabled:

- Dark means `sensor value > dark threshold`.
- Bright means `sensor value < bright threshold`.

When it is disabled:

- Dark means `sensor value < dark threshold`.
- Bright means `sensor value > bright threshold`.

Unknown, unavailable, missing, or non-numeric sensor states satisfy neither comparison and cause no action.

## Execution Behavior

The automation uses `parallel` mode with a small bounded maximum number of runs. This ensures that a harmless arrival or startup evaluation does not cancel a long-running fade already in progress. The monitored-light state checks suppress duplicate actions once the light has begun turning on or off.

The dark and bright thresholds are deliberately separated, so opposing action sequences should not normally overlap. Because the action inputs are intentionally generic, responsibility for canceling or coordinating two external long-running scripts remains with those scripts. Ashley's Light Fader has its own cancellation behavior and can be configured in the supplied action sequences.

## No Additional Helpers

The blueprint uses no text, counter, timer, boolean, or other helper entities. Hold-time tracking is provided by Home Assistant triggers. As with native Home Assistant `for` triggers, an in-progress hold is reset by an automation reload or Home Assistant restart. The startup evaluation provides recovery by checking the current state after a 30-second settling delay.

## Validation

Repository validation will cover:

- YAML parsing with Home Assistant's `!input` tags supported by the test loader.
- Required blueprint metadata, selectors, defaults, and author credit.
- Trigger IDs for dark hold, bright hold, arrival, awake start, and Home Assistant start.
- Both high-is-dark and low-is-dark comparison branches.
- Shared turn-on guards for darkness, presence, awake time, and monitored-light state.
- Bright-path independence from presence and awake time.
- Generic action inputs used in their corresponding branches.
- Parallel execution mode and bounded maximum runs.
- No helper-entity inputs or dependencies.

The final review will also inspect the Home Assistant UI descriptions to ensure the threshold direction, hold behavior, restart recovery, and optional Ashley's Light Fader configuration are understandable without reading the YAML source.

## Publication

After validation and review, the implementation will be committed to the repository and pushed to its configured `origin` on the current branch.
