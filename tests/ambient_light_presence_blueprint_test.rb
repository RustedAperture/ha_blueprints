require "minitest/autorun"
require "yaml"

class AmbientLightPresenceBlueprintTest < Minitest::Test
  PATH = File.expand_path("../blueprints/automation/ambient_light_presence/ambient_light_presence.yaml", __dir__)

  def doc
    @doc ||= YAML.load_file(PATH)
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
