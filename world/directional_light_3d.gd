extends DirectionalLight3D
## The sun, and the clock it keeps. Select DirectionalLight3D in the world scene to set how long
## day and night last.

## How many real minutes the day lasts, from sunrise to sunset (dawn and dusk included)
@export var day_minutes := 28.0
## How many real minutes the night lasts, from sunset to sunrise
@export var night_minutes := 12.0
## Where the day starts: 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset
@export_range(0.0, 1.0) var time_of_day := 0.3
## The sky, so it can dim at night
@export var world_environment: WorldEnvironment

## 1 in full daylight, 0 at night. The player reads this to know how cold it is.
var daylight := 1.0
## How many midnights have passed since the game began
var day := 0


func _ready() -> void:
	add_to_group("sun")
	if not Engine.is_editor_hint():
		add_to_group("saveable")


## Days since the game began, with the part of today that's gone: 2.5 is noon on the third day
func total_days() -> float:
	return day + time_of_day


func save_key() -> String:
	return "clock"


func save_priority() -> int:
	return 0


func save_data() -> Dictionary:
	return {"time_of_day": time_of_day, "day": day}


func load_data(data: Dictionary) -> void:
	time_of_day = float(data.get("time_of_day", time_of_day))
	day = int(data.get("day", day))


## How many real seconds the day lasts (sunrise to sunset)
func day_seconds() -> float:
	return maxf(day_minutes, 0.1) * 60.0


## How many real seconds the night lasts (sunset to sunrise)
func night_seconds() -> float:
	return maxf(night_minutes, 0.1) * 60.0


## How many real seconds a whole day and night take
func cycle_seconds() -> float:
	return day_seconds() + night_seconds()


func _process(delta: float) -> void:
	# Move time forward: the half of the clock from sunrise to sunset takes day_minutes, the other
	# half takes night_minutes. It wraps back to midnight after a full day.
	var is_day := time_of_day >= 0.25 and time_of_day < 0.75
	var later := time_of_day + delta * 0.5 / (day_seconds() if is_day else night_seconds())
	if later >= 1.0:
		day += 1
	time_of_day = fmod(later, 1.0)

	# Swing the sun around: level at sunrise, straight down at noon
	rotation.x = -(time_of_day - 0.25) * TAU

	# How high the sun is: 1 at noon, 0 at the horizon, below 0 at night
	var sun_height := sin((time_of_day - 0.25) * TAU)
	daylight = clampf(sun_height * 3.0, 0.0, 1.0)

	# Fade the sunlight, and warm it to orange near sunrise and sunset
	light_energy = daylight
	light_color = Color(1.0, 0.55, 0.3).lerp(Color.WHITE, clampf(sun_height * 2.0, 0.0, 1.0))

	# Dim the sky and its glow for night
	if world_environment:
		var env := world_environment.environment
		env.background_energy_multiplier = lerpf(0.05, 1.0, daylight)
		env.ambient_light_energy = lerpf(0.1, 1.0, daylight)
