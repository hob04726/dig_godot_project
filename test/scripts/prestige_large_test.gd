extends SceneTree

## 测试大升华点数下的 Prestige 行为

func _init() -> void:
	var cases := [
		{"lifetime": "101000000080000000", "expected_points": "101000000082", "expected_remaining": "1000000"},
		{"lifetime": "101000000081000000", "expected_points": "101000000083", "expected_remaining": "1000000"},
		{"lifetime": "100000000000000000", "expected_points": "100000000002", "expected_remaining": "1000000"},
	]
	
	var failures := 0
	for case in cases:
		var lifetime := BigNumber.from_string(case.lifetime)
		var points := Prestige.points_for(lifetime)
		var remaining := Prestige.coins_to_next_point(lifetime)
		var exp_points := BigNumber.from_string(case.expected_points)
		var exp_remaining := BigNumber.from_string(case.expected_remaining)
		
		var ok1 := points.eq(exp_points)
		var ok2 := remaining.eq(exp_remaining)
		if ok1 and ok2:
			print("[通过] lifetime=%s -> points=%s, remaining=%s" % [case.lifetime, points.to_full_string(), remaining.to_compact_string()])
		else:
			failures += 1
			print("[失败] lifetime=%s" % case.lifetime)
			print("  expected points=%s, got %s" % [exp_points.to_full_string(), points.to_full_string()])
			print("  expected remaining=%s, got %s" % [exp_remaining.to_full_string(), remaining.to_full_string()])
	
	print("=== prestige_large_test：失败 %d 处 ===" % failures)
	quit(1 if failures > 0 else 0)
