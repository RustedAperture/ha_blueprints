# Ambient Light and Presence Lighting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a generic Home Assistant blueprint that turns lighting on when darkness, presence, awake-time, and light-state checks pass, then runs a configurable off action after sustained brightness.

**Architecture:** One automation blueprint owns threshold evaluation and event routing. Template triggers normalize both sensor directions; arrival, awake-start, and Home Assistant-start triggers recover missed dark crossings; generic action inputs keep Ashley's Light Fader optional.

**Tech Stack:** Home Assistant blueprint YAML, Jinja templates, Ruby standard-library YAML parser, Minitest

**Spec:** `docs/superpowers/specs/2026-09-13-ambient-light-presence-lighting-design.md`

## Global Constraints

- Create `blueprints/automation/ambient_light_presence/ambient_light_presence.yaml` in `RustedAperture/ha_blueprints`.
- Credit RustedAperture and use the final GitHub file URL as `source_url`.
- Require no helper entities.
- Default thresholds to dark `2800` and bright `500`; default both holds to 5 minutes.
- Default awake time to `07:00:00` through `23:00:00`.
- Allow either high-is-dark or low-is-dark numeric sensors.
- Require darkness, one selected person home, awake time, and monitored light off for the on action.
- Require only the monitored light on for the brightness-driven off action.
- Do not trigger from manual light changes or the awake end time.
- Use generic action selectors and `parallel` mode with `max: 10`.

---

### Task 1: Add the blueprint and its contract test

**Files:**
- Create: `tests/ambient_light_presence_blueprint_test.rb`
- Create: `blueprints/automation/ambient_light_presence/ambient_light_presence.yaml`

**Interfaces:**
- Consumes: one numeric sensor, one or more person entities, one light entity, thresholds, durations, times, and two Home Assistant action sequences.
- Produces: `turn_on_action` and `turn_off_action` routing from five named triggers.

- [ ] **Step 1: Write the failing contract test**

Create `tests/ambient_light_presence_blueprint_test.rb`:

```ruby
require "minitest/autorun"
require "yaml"

class AmbientLightPresenceBlueprintTest < Minitest::Test
  PATH = File.expand_path("../blueprints/automation/ambient_light_presence/ambient_light_presence.yaml", __dir__)

  def doc
    @doc ||= YAML.load_file(PATH, aliases: true)
  end

  def metadata
    doc.fetch("blueprint")
  end

  def inputs
    metadata.fetch("input")
  end

  def triggers
    doc.fetch("triggers")
  end

  def test_metadata
    assert_equal "automation", metadata.fetch("domain")
    assert_equal "RustedAperture", metadata.fetch("author")
    assert_equal "https://github.com/RustedAperture/ha_blueprints/blob/main/blueprints/automation/ambient_light_presence/ambient_light_presence.yaml", metadata.fetch("source_url")
  end

  def test_inputs_and_defaults
    assert_equal %w[ambient_sensor higher_values_mean_darker dark_threshold bright_threshold dark_hold_time bright_hold_time people awake_start_time awake_end_time monitored_light turn_on_action turn_off_action], inputs.keys
    assert_equal true, inputs.dig("higher_values_mean_darker", "default")
    assert_equal 2800, inputs.dig("dark_threshold", "default")
    assert_equal 500, inputs.dig("bright_threshold", "default")
    expected_hold = { "hours" => 0, "minutes" => 5, "seconds" => 0 }
    assert_equal expected_hold, inputs.dig("dark_hold_time", "default")
    assert_equal expected_hold, inputs.dig("bright_hold_time", "default")
    assert_equal "07:00:00", inputs.dig("awake_start_time", "default")
    assert_equal "23:00:00", inputs.dig("awake_end_time", "default")
    assert_equal true, inputs.dig("people", "selector", "entity", "multiple")
    assert_equal "person", inputs.dig("people", "selector", "entity", "filter", "domain")
    assert_equal "light", inputs.dig("monitored_light", "selector", "entity", "filter", "domain")
    assert_equal({}, inputs.dig("turn_on_action", "selector", "action"))
    assert_equal({}, inputs.dig("turn_off_action", "selector", "action"))
  end

  def test_triggers
    assert_equal %w[dark_held bright_held person_arrived awake_start home_assistant_started], triggers.map { |item| item.fetch("id") }
    dark = triggers.fetch(0)
    bright = triggers.fetch(1)
    assert_equal "template", dark.fetch("trigger")
    assert_equal "dark_hold_time", dark.fetch("for")
    assert_includes dark.fetch("value_template"), "higher_values_mean_darker_trigger"
    assert_equal "template", bright.fetch("trigger")
    assert_equal "bright_hold_time", bright.fetch("for")
    assert_includes bright.fetch("value_template"), "higher_values_mean_darker_trigger"
    assert_equal "people", triggers.fetch(2).fetch("entity_id")
    assert_equal "home", triggers.fetch(2).fetch("to")
    refute triggers.fetch(2).key?("for")
    assert_equal "awake_start_time", triggers.fetch(3).fetch("at")
    assert_equal "start", triggers.fetch(4).fetch("event")
  end

  def test_action_routing_and_no_helpers
    assert_equal "parallel", doc.fetch("mode")
    assert_equal 10, doc.fetch("max")
    actions = doc.fetch("actions")
    assert_equal "00:00:30", actions.fetch(0).fetch("then").fetch(0).fetch("delay")
    on_choice, off_choice = actions.fetch(1).fetch("choose")
    assert_equal %w[dark_held person_arrived awake_start home_assistant_started], on_choice.fetch("conditions").fetch(0).fetch("id")
    assert_equal "turn_on_action", on_choice.fetch("sequence")
    assert_includes on_choice.fetch("conditions").to_s, "people_entities"
    assert_includes on_choice.fetch("conditions").to_s, "awake_start_time"
    assert_equal ["bright_held"], off_choice.fetch("conditions").fetch(0).fetch("id")
    assert_equal "turn_off_action", off_choice.fetch("sequence")
    refute_includes off_choice.fetch("conditions").to_s, "people_entities"
    refute_includes off_choice.fetch("conditions").to_s, "awake_start_time"
    refute_match(/helper|counter|timer|input_text|input_boolean/, inputs.keys.join(" "))
  end
end
```

- [ ] **Step 2: Run the test and confirm the missing blueprint failure**

Run: `ruby tests/ambient_light_presence_blueprint_test.rb`

Expected: an error stating that `ambient_light_presence.yaml` does not exist.

- [ ] **Step 3: Implement the blueprint metadata and inputs**

Create the blueprint with `homeassistant.min_version: 2024.10.0`. Define these inputs in this exact order and shape:

| Input | Selector | Default |
|---|---|---|
| `ambient_sensor` | one `sensor` entity | required |
| `higher_values_mean_darker` | boolean | `true` |
| `dark_threshold` | box number, -100000 through 100000, step 1 | `2800` |
| `bright_threshold` | box number, -100000 through 100000, step 1 | `500` |
| `dark_hold_time` | duration | 5 minutes |
| `bright_hold_time` | duration | 5 minutes |
| `people` | multiple `person` entities | required |
| `awake_start_time` | time | `07:00:00` |
| `awake_end_time` | time | `23:00:00` |
| `monitored_light` | one `light` entity | required |
| `turn_on_action` | action | `[]` |
| `turn_off_action` | action | `[]` |

Use this metadata:

```yaml
blueprint:
  name: Ambient Light & Presence Lighting
  domain: automation
  author: RustedAperture
  source_url: https://github.com/RustedAperture/ha_blueprints/blob/main/blueprints/automation/ambient_light_presence/ambient_light_presence.yaml
  homeassistant:
    min_version: 2024.10.0
```

The description must state that actions are generic, no helpers are required, arrival/awake-start/startup recover missed crossings, and Ashley's Light Fader can fade fully off with `endBrightnessPercent: 0`.

- [ ] **Step 4: Implement sensor-direction trigger templates**

Expose the four sensing inputs as `trigger_variables` and use these exact comparison rules in the `dark_held` and `bright_held` template triggers:

```yaml
trigger_variables:
  ambient_sensor_trigger: !input ambient_sensor
  higher_values_mean_darker_trigger: !input higher_values_mean_darker
  dark_threshold_trigger: !input dark_threshold
  bright_threshold_trigger: !input bright_threshold

triggers:
  - trigger: template
    id: dark_held
    value_template: >-
      {% set reading = states(ambient_sensor_trigger) %}
      {% if not (reading | is_number) %}
        false
      {% elif higher_values_mean_darker_trigger %}
        {{ (reading | float) > (dark_threshold_trigger | float) }}
      {% else %}
        {{ (reading | float) < (dark_threshold_trigger | float) }}
      {% endif %}
    for: !input dark_hold_time
  - trigger: template
    id: bright_held
    value_template: >-
      {% set reading = states(ambient_sensor_trigger) %}
      {% if not (reading | is_number) %}
        false
      {% elif higher_values_mean_darker_trigger %}
        {{ (reading | float) < (bright_threshold_trigger | float) }}
      {% else %}
        {{ (reading | float) > (bright_threshold_trigger | float) }}
      {% endif %}
    for: !input bright_hold_time
```

Append the `person_arrived` state trigger for all selected people changing to `home`, the `awake_start` time trigger, and the `home_assistant_started` Home Assistant start trigger.

- [ ] **Step 5: Implement guarded action routing**

Define action variables for the ambient sensor, direction, dark threshold, and people. First delay startup-triggered runs for 30 seconds. Then use one `choose` with:

- On trigger IDs: `dark_held`, `person_arrived`, `awake_start`, `home_assistant_started`.
- On template: reject non-numeric readings; otherwise apply the selected dark comparison.
- On presence template: `expand(people_entities) | selectattr('state', 'eq', 'home') | list | count > 0`.
- On time condition: `after: !input awake_start_time` and `before: !input awake_end_time`.
- On light condition: `!input monitored_light` is `off`.
- On sequence: `!input turn_on_action`.
- Off trigger ID: `bright_held` only.
- Off light condition: `!input monitored_light` is `on`.
- Off sequence: `!input turn_off_action`.

Finish with:

```yaml
mode: parallel
max: 10
max_exceeded: warning
```

- [ ] **Step 6: Run the contract and repository checks**

Run:

```bash
ruby -c tests/ambient_light_presence_blueprint_test.rb
ruby tests/ambient_light_presence_blueprint_test.rb
git diff --check
git status --short
```

Expected: valid Ruby syntax, 4 tests with 0 failures and 0 errors, no whitespace errors, and only the planned blueprint/test/plan files changed.

- [ ] **Step 7: Review against the specification**

Verify that the off branch has no presence or awake-time gate; no awake-end or monitored-light trigger exists; the startup delay affects only startup runs; both sensor directions reject invalid readings; and the UI descriptions explain hysteresis, restart behavior, manual-off behavior, and optional Ashley fading.

- [ ] **Step 8: Commit, verify the committed tree, and publish**

Run:

```bash
git add blueprints/automation/ambient_light_presence/ambient_light_presence.yaml tests/ambient_light_presence_blueprint_test.rb docs/superpowers/plans/2026-09-13-ambient-light-presence-lighting.md
git commit -m "Add ambient light presence blueprint"
ruby tests/ambient_light_presence_blueprint_test.rb
git status --short
git log -2 --oneline
git push origin main
```

Expected: tests still pass, the worktree is clean, the implementation commit follows the design commit, and `origin/main` advances to the implementation commit.
