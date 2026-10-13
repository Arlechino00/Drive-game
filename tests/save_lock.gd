extends SceneTree

class ReplacedDuringProof:
	extends "res://scripts/save_lock.gd"
	var replacement_path := ""
	var proofs := 0

	func _owner_is_dead(_owner: Dictionary) -> bool:
		proofs += 1
		if proofs == 2:
			var file := FileAccess.open(replacement_path.path_join("owner.json"), FileAccess.WRITE)
			file.store_string(JSON.stringify({"version": 1, "pid": OS.get_process_id(), "platform": OS.get_name(), "token": "c".repeat(32)}))
			file.close()
		return true

var failures := 0
var lock_script: Script
var prefix := "user://test-save-lock-%s" % Time.get_ticks_usec()


func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/save_lock.gd"):
		_check(false, "owned save locks support safe abandoned-owner recovery")
		quit(1)
		return
	lock_script = load("res://scripts/save_lock.gd")
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--hold":
		var held: Variant = lock_script.new()
		if held.acquire(args[1]) != OK:
			quit(2)
			return
		_touch(args[1] + ".ready")
		return # Parent kills this deliberately, leaving an owned lock.
	if args.size() >= 3 and args[0] == "--race":
		while not FileAccess.file_exists(args[2]):
			await process_frame
		var contender: Variant = lock_script.new()
		var result: int = contender.acquire(args[1])
		if result == OK:
			if FileAccess.file_exists(args[1] + ".active"):
				quit(3)
				return
			_touch(args[1] + ".active")
			await create_timer(0.5).timeout
			DirAccess.remove_absolute(args[1] + ".active")
			contender.release()
		quit(0 if result == OK or result == ERR_BUSY else 4)
		return
	_test_exclusivity()
	_test_unknown()
	_test_replacement_during_recovery()
	await _test_process_owner()
	if failures == 0:
		print("SAVE LOCK PASS: exclusive owned writes, live processes retained, killed-owner recovery, malformed/legacy retention, simultaneous recovery contenders")
	quit(1 if failures else 0)


func _test_exclusivity() -> void:
	var path := prefix + "-live.lock"
	var first: Variant = lock_script.new()
	var second: Variant = lock_script.new()
	_check(first.acquire(path) == OK, "first writer acquires lock")
	_check(FileAccess.file_exists(path.path_join("owner.json")), "identity published before acquire returns")
	_check(second.acquire(path) == ERR_BUSY, "another writer cannot steal current-process lock")
	second.release()
	_check(DirAccess.dir_exists_absolute(path), "failed contender release preserves owner")
	first.release()
	_check(not DirAccess.dir_exists_absolute(path), "owner releases lock")
	_check(second.acquire(path) == OK, "released lock can be acquired")
	second.release()
	second.release()
	_check(not DirAccess.dir_exists_absolute(path), "release is idempotent")
	_check(first.acquire(path) == OK, "replacement fixture acquired")
	var replacement := FileAccess.get_file_as_string(path.path_join("owner.json"))
	var owner: Dictionary = JSON.parse_string(replacement)
	owner.token = "b".repeat(32)
	_touch(path.path_join("owner.json"), JSON.stringify(owner))
	first.release()
	_check(FileAccess.file_exists(path.path_join("owner.json")), "release does not delete replacement owner")
	DirAccess.remove_absolute(path.path_join("owner.json"))
	DirAccess.remove_absolute(path)


func _test_unknown() -> void:
	for state in ["legacy", "malformed", "invalid-pid", "invalid-token", "other-platform"]:
		var path: String = prefix + "-" + state + ".lock"
		DirAccess.make_dir_absolute(path)
		if state == "malformed":
			_touch(path.path_join("owner.json"), "unclosed=[")
		elif state != "legacy":
			var config := {}
			config["version"] = 1
			config["pid"] = -1 if state == "invalid-pid" else OS.get_process_id()
			config["token"] = "x".repeat(32) if state == "invalid-token" else "a".repeat(32)
			config["platform"] = "unknown" if state == "other-platform" else OS.get_name()
			_touch(path.path_join("owner.json"), JSON.stringify(config))
		var contender: Variant = lock_script.new()
		_check(contender.acquire(path) == ERR_BUSY, "%s lock retained" % state)
		_check(DirAccess.dir_exists_absolute(path), "%s directory untouched" % state)
		DirAccess.remove_absolute(path.path_join("owner.json"))
		DirAccess.remove_absolute(path)


func _test_replacement_during_recovery() -> void:
	var path := prefix + "-replace.lock"
	var original: Variant = lock_script.new()
	_check(original.acquire(path) == OK, "recovery replacement fixture acquired")
	var contender := ReplacedDuringProof.new()
	contender.replacement_path = path
	_check(contender.acquire(path) == ERR_BUSY, "owner replacement during liveness proof prevents reclamation")
	var owner: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("owner.json")))
	_check(owner.get("token") == "c".repeat(32), "replacement identity retained after failed reclamation")
	contender.release()
	original.release()
	DirAccess.remove_absolute(path.path_join("owner.json"))
	DirAccess.remove_absolute(path)


func _test_process_owner() -> void:
	var path := prefix + "-child.lock"
	var pid := _spawn(["--hold", path])
	_check(pid > 0, "separate process spawned")
	if pid <= 0:
		return
	var ready := await _wait_file(path + ".ready")
	_check(ready, "separate process acquired lock")
	var contender: Variant = lock_script.new()
	if ready:
		_check(contender.acquire(path) == ERR_BUSY, "another live process owner retained")
	_check(OS.kill(pid) == OK, "owned child terminated to simulate crash")
	await _wait_exit(pid)
	DirAccess.remove_absolute(path + ".ready")
	if OS.get_name() != "Windows":
		_check(contender.acquire(path) == ERR_BUSY, "unverified platform retains dead owner")
		return
	_check(contender.acquire(path) == OK, "demonstrably killed owner recovered")
	contender.release()
	_check(not DirAccess.dir_exists_absolute(path), "recovered lock releases")
	# Recreate a killed owner and release four simultaneous contenders at once.
	pid = _spawn(["--hold", path])
	ready = await _wait_file(path + ".ready")
	_check(ready, "race fixture owns lock")
	OS.kill(pid)
	await _wait_exit(pid)
	DirAccess.remove_absolute(path + ".ready")
	var children: Array[int] = []
	for index in range(4):
		children.append(_spawn(["--race", path, path + ".go"]))
	_touch(path + ".go")
	for child in children:
		await _wait_exit(child)
		_check(OS.get_process_exit_code(child) == 0, "recovery contender finishes without overlapping owners")
	DirAccess.remove_absolute(path + ".go")
	_check(not DirAccess.dir_exists_absolute(path), "race leaves lock available")


func _spawn(args: PackedStringArray) -> int:
	return OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/save_lock.gd", "--"]) + args)


func _wait_file(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await process_frame
	return FileAccess.file_exists(path)


func _wait_exit(pid: int) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await process_frame
	if OS.is_process_running(pid):
		OS.kill(pid)
		_check(false, "child process finishes within deadline")


func _touch(path: String, value: String = "ready") -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
