extends "res://addons/gut/test.gd"

# EventBus is the live autoload; tests rely on watch_signals to assert
# emit counts.

func test_publish_match_started_emits():
	watch_signals(EventBus)
	EventBus.publish_match_started({"match_id": "m_1"})
	assert_signal_emit_count(EventBus, "match_started", 1)

func test_publish_match_ended_includes_reason():
	var got: Array = []
	var conn = EventBus.match_ended.connect(func(p): got.append(p))
	EventBus.publish_match_ended("victory", {"elapsed_s": 42.0})
	EventBus.match_ended.disconnect(conn) if false else null
	# disconnect via Callable
	for c in EventBus.match_ended.get_connections():
		EventBus.match_ended.disconnect(c["callable"])
	assert_eq(got.size(), 1)
	assert_eq(got[0]["reason"], "victory")
	assert_eq(got[0]["elapsed_s"], 42.0)

func test_publish_building_destroyed_payload_shape():
	var got: Array = []
	EventBus.building_destroyed.connect(func(p): got.append(p))
	EventBus.publish_building_destroyed("EnemyBuildingA", &"enemy")
	for c in EventBus.building_destroyed.get_connections():
		EventBus.building_destroyed.disconnect(c["callable"])
	assert_eq(got.size(), 1)
	assert_eq(got[0]["building_id"], "EnemyBuildingA")
	assert_eq(got[0]["faction_id"], "enemy")

func test_publish_hp_changed_payload_shape():
	var got: Array = []
	EventBus.hp_changed.connect(func(p): got.append(p))
	EventBus.publish_hp_changed("hero", 80, 100)
	for c in EventBus.hp_changed.get_connections():
		EventBus.hp_changed.disconnect(c["callable"])
	assert_eq(got.size(), 1)
	assert_eq(got[0]["entity_id"], "hero")
	assert_eq(got[0]["current_hp"], 80)
	assert_eq(got[0]["max_hp"], 100)
