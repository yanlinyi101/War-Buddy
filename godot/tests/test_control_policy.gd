extends "res://addons/gut/test.gd"

const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

func test_full_control_accepts_everything():
	var p = ControlPolicyScript.FullControlPolicy.new()
	assert_true(p.can_issue(TacticalOrderScript.Issuer.PLAYER, &"deputy", &"move"))
	assert_true(p.can_issue(TacticalOrderScript.Issuer.DEPUTY, &"deputy", &"attack"))

func test_hero_only_accepts_only_player_with_empty_deputy():
	var p = ControlPolicyScript.HeroOnlyPolicy.new()
	assert_true(p.can_issue(TacticalOrderScript.Issuer.PLAYER, &"", &"move"))
	assert_false(p.can_issue(TacticalOrderScript.Issuer.PLAYER, &"deputy", &"move"))
	assert_false(p.can_issue(TacticalOrderScript.Issuer.DEPUTY, &"", &"attack"))

func test_assist_mode_accepts_player_and_logs_deputy_as_suggestion():
	var p = ControlPolicyScript.AssistModePolicy.new()
	assert_true(p.can_issue(TacticalOrderScript.Issuer.PLAYER, &"", &"move"))
	# Deputy plans are still rejected at can_issue level — `assist` semantics in the
	# bus simply log them; the policy says no.
	assert_false(p.can_issue(TacticalOrderScript.Issuer.DEPUTY, &"deputy", &"attack"))

func test_archon_rejects_llm_deputy_for_attached_seat():
	var p = ControlPolicyScript.ArchonControlPolicy.new(&"deputy")
	# Human archon as PLAYER on attached seat = OK
	assert_true(p.can_issue(TacticalOrderScript.Issuer.PLAYER, &"deputy", &"move"))
	# LLM deputy on the attached seat = blocked
	assert_false(p.can_issue(TacticalOrderScript.Issuer.DEPUTY, &"deputy", &"move"))
	# LLM deputy on an unattached seat (e.g. captain) = OK
	assert_true(p.can_issue(TacticalOrderScript.Issuer.DEPUTY, &"deputy_other", &"move"))

func test_archon_with_empty_attached_seat_behaves_like_full_control():
	var p = ControlPolicyScript.ArchonControlPolicy.new(&"")
	assert_true(p.can_issue(TacticalOrderScript.Issuer.DEPUTY, &"deputy", &"move"))
