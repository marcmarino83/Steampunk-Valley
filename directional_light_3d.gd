extends DirectionalLight3D

## How many real seconds one full day lasts
@export var day_length := 120.0
## Where the day starts: 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset
@export_range(0.0, 1.0) var time_of_day := 0.3
## The sky, so it can dim at night
@export var world_environment: WorldEnvironment


func _process(delta: float) -> void:
	# Move time forward, wrapping back to midnight after a full day
	time_of_day = fmod(time_of_day + delta / day_length, 1.0)

	# Swing the sun around: level at sunrise, straight down at noon
	rotation.x = -(time_of_day - 0.25) * TAU

	# How high the sun is: 1 at noon, 0 at the horizon, below 0 at night
	var sun_height := sin((time_of_day - 0.25) * TAU)
	var daylight := clampf(sun_height * 3.0, 0.0, 1.0)

	# Fade the sunlight, and warm it to orange near sunrise and sunset
	light_energy = daylight
	light_color = Color(1.0, 0.55, 0.3).lerp(Color.WHITE, clampf(sun_height * 2.0, 0.0, 1.0))

	# Dim the sky and its glow for night
	if world_environment:
		var env := world_environment.environment
		env.background_energy_multiplier = lerpf(0.05, 1.0, daylight)
		env.ambient_light_energy = lerpf(0.1, 1.0, daylight)