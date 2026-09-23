require "minitest/autorun"
require "yaml"

class AmbientLightPresenceBlueprintTest < Minitest::Test
  PATH = File.expand_path(ENV.fetch("AMBIENT_LIGHT_PRESENCE_BLUEPRINT", "../blueprints/automation/ambient_light_presence/ambient_light_presence.yaml"), __dir__)

  def doc
    @doc ||= YAML.load_file(PATH)
  end

  def ast
    @ast ||= Psych.parse_file(PATH).root
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

  def input_references
    references = []
    visit = lambda do |node|
      references << node.value if node.is_a?(Psych::Nodes::Scalar) && node.tag == "!input"
      node.children.to_a.each { |child| visit.call(child) } if node.respond_to?(:children)
    end
    visit.call(ast)
    references
  end

  def structural_strings(value, key = nil)
    return [] if key == "description"

    case value
    when Hash
      value.flat_map { |child_key, child_value| [child_key.to_s] + structural_strings(child_value, child_key) }
    when Array
      value.flat_map { |child| structural_strings(child) }
    else
      [value.to_s]
    end
  end

  def assert_template_equal(expected, actual)
    assert_equal expected.gsub(/\s+/, " ").strip, actual.gsub(/\s+/, " ").strip
  end

  def test_metadata
    assert_equal "automation", metadata.fetch("domain")
    assert_equal "RustedAperture", metadata.fetch("author")
    assert_equal "https://github.com/RustedAperture/ha_blueprints/blob/main/blueprints/automation/ambient_light_presence/ambient_light_presence.yaml", metadata.fetch("source_url")
    assert_equal "2024.10.0", metadata.dig("homeassistant", "min_version")
  end

  def test_inputs_and_defaults
    assert_equal %w[ambient_sensor higher_values_mean_darker dark_threshold bright_threshold dark_hold_time bright_hold_time people awake_start_time awake_end_time monitored_light turn_on_action use_arrival_turn_on_action arrival_turn_on_action turn_off_action], inputs.keys
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
    assert_equal false, inputs.dig("use_arrival_turn_on_action", "default")
    assert_equal({}, inputs.dig("use_arrival_turn_on_action", "selector", "boolean"))
    assert_equal [], inputs.dig("arrival_turn_on_action", "default")
    assert_equal({}, inputs.dig("arrival_turn_on_action", "selector", "action"))
    assert_equal({}, inputs.dig("turn_off_action", "selector", "action"))
  end

  def test_all_input_references_are_tagged
    expected = {
      "ambient_sensor" => 2,
      "higher_values_mean_darker" => 2,
      "dark_threshold" => 2,
      "bright_threshold" => 1,
      "dark_hold_time" => 1,
      "bright_hold_time" => 1,
      "people" => 2,
      "awake_start_time" => 2,
      "awake_end_time" => 1,
      "monitored_light" => 2,
      "turn_on_action" => 1,
      "use_arrival_turn_on_action" => 1,
      "arrival_turn_on_action" => 1,
      "turn_off_action" => 1
    }
    counts = input_references.each_with_object(Hash.new(0)) { |name, result| result[name] += 1 }
    assert_equal expected, counts
    assert_equal %w[ambient_sensor higher_values_mean_darker dark_threshold bright_threshold dark_hold_time bright_hold_time people awake_start_time ambient_sensor higher_values_mean_darker dark_threshold people use_arrival_turn_on_action awake_start_time awake_end_time monitored_light arrival_turn_on_action turn_on_action monitored_light turn_off_action], input_references
    refute_match(/helper|counter|timer|input_text|input_boolean/, structural_strings(doc).join(" "))
  end

  def test_triggers_and_exact_direction_templates
    assert_equal %w[dark_held bright_held person_arrived awake_start home_assistant_started], triggers.map { |item| item.fetch("id") }
    dark = triggers.fetch(0)
    bright = triggers.fetch(1)
    assert_equal "template", dark.fetch("trigger")
    assert_equal "dark_hold_time", dark.fetch("for")
    assert_template_equal <<~TEMPLATE, dark.fetch("value_template")
      {% set reading = states(ambient_sensor_trigger) %}
      {% if not (reading | is_number) %}
        false
      {% elif higher_values_mean_darker_trigger %}
        {{ (reading | float) > (dark_threshold_trigger | float) }}
      {% else %}
        {{ (reading | float) < (dark_threshold_trigger | float) }}
      {% endif %}
    TEMPLATE
    assert_equal "template", bright.fetch("trigger")
    assert_equal "bright_hold_time", bright.fetch("for")
    assert_template_equal <<~TEMPLATE, bright.fetch("value_template")
      {% set reading = states(ambient_sensor_trigger) %}
      {% if not (reading | is_number) %}
        false
      {% elif higher_values_mean_darker_trigger %}
        {{ (reading | float) < (bright_threshold_trigger | float) }}
      {% else %}
        {{ (reading | float) > (bright_threshold_trigger | float) }}
      {% endif %}
    TEMPLATE
    assert_equal "state", triggers.fetch(2).fetch("trigger")
    assert_equal "people", triggers.fetch(2).fetch("entity_id")
    assert_equal "home", triggers.fetch(2).fetch("to")
    refute triggers.fetch(2).key?("for")
    assert_equal({ "trigger" => "time", "id" => "awake_start", "at" => "awake_start_time" }, triggers.fetch(3))
    assert_equal({ "trigger" => "homeassistant", "id" => "home_assistant_started", "event" => "start" }, triggers.fetch(4))
  end

  def test_action_routing_and_guards
    assert_equal "parallel", doc.fetch("mode")
    assert_equal 10, doc.fetch("max")
    assert_equal "warning", doc.fetch("max_exceeded")
    actions = doc.fetch("actions")
    assert_equal 2, actions.length
    startup_guard = actions.fetch(0)
    assert_equal [{ "condition" => "trigger", "id" => "home_assistant_started" }], startup_guard.fetch("if")
    assert_equal [{ "delay" => "00:00:30" }], startup_guard.fetch("then")

    on_choice, off_choice = actions.fetch(1).fetch("choose")
    on_conditions = on_choice.fetch("conditions")
    assert_equal [{ "condition" => "trigger", "id" => %w[dark_held person_arrived awake_start home_assistant_started] }], on_conditions.first(1)
    assert_template_equal <<~TEMPLATE, on_conditions.fetch(1).fetch("value_template")
      {% set reading = states(ambient_sensor_entity) %}
      {% if not (reading | is_number) %}
        false
      {% elif higher_values_mean_darker_entity %}
        {{ (reading | float) > (dark_threshold_entity | float) }}
      {% else %}
        {{ (reading | float) < (dark_threshold_entity | float) }}
      {% endif %}
    TEMPLATE
    assert_equal({ "condition" => "template", "value_template" => "{{ expand(people_entities) | selectattr('state', 'eq', 'home') | list | count > 0 }}" }, on_conditions.fetch(2))
    assert_equal({ "condition" => "time", "after" => "awake_start_time", "before" => "awake_end_time" }, on_conditions.fetch(3))
    assert_equal({ "condition" => "state", "entity_id" => "monitored_light", "state" => "off" }, on_conditions.fetch(4))
    assert_kind_of Array, on_choice.fetch("sequence")
    arrival_routing = on_choice.fetch("sequence").fetch(0)
    arrival_choice = arrival_routing.fetch("choose").fetch(0)
    assert_equal({ "condition" => "trigger", "id" => "person_arrived" }, arrival_choice.fetch("conditions").fetch(0))
    assert_equal({ "condition" => "template", "value_template" => "{{ use_arrival_turn_on_action_input }}" }, arrival_choice.fetch("conditions").fetch(1))
    assert_equal "arrival_turn_on_action", arrival_choice.fetch("sequence")
    assert_equal "turn_on_action", arrival_routing.fetch("default")
    assert_equal "use_arrival_turn_on_action", doc.fetch("variables").fetch("use_arrival_turn_on_action_input")
    refute_includes doc.fetch("variables").values, "arrival_turn_on_action"

    off_conditions = off_choice.fetch("conditions")
    assert_equal 2, off_conditions.length
    assert_equal({ "condition" => "trigger", "id" => ["bright_held"] }, off_conditions.fetch(0))
    assert_equal({ "condition" => "state", "entity_id" => "monitored_light", "state" => "on" }, off_conditions.fetch(1))
    assert_equal "turn_off_action", off_choice.fetch("sequence")
  end
end
