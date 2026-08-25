extends SceneTree

func _init() -> void:
	var lifetime := BigNumber.from_string("101000000080000000")
	print("lifetime to_float = %.1f" % lifetime.to_float())
	
	var points := BigNumber.from_int(101_000_000_083)
	var next_threshold := Prestige.threshold_for_points(points)
	print("next_threshold mantissa=%.12f exponent=%d" % [next_threshold.mantissa, next_threshold.exponent])
	print("next_threshold to_float = %.1f" % next_threshold.to_float())
	print("next_threshold full = %s" % next_threshold.to_full_string())
	
	quit()
