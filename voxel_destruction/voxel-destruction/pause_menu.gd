extends CanvasLayer

var world = null
var is_resetting = false  # Flaga zapobiegająca wielokrotnemu resetowaniu

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("find_world")

func find_world():
	"""Znajduje węzeł świata w drzewie sceny"""
	var root = get_tree().root
	if root.get_child_count() > 0:
		# Sprawdź główny node
		world = root.get_child(0)
		
		# Jeśli główny node nie ma metody generate_world_fast, szukaj dalej
		if not world.has_method("generate_world_fast"):
			for child in root.get_children():
				if child.has_method("generate_world_fast"):
					world = child
					break
	
	if world:
		print("Menu pauzy: Znaleziono świat - ", world.name)
	else:
		print("BŁĄD: Menu pauzy nie znalazło świata!")

func _input(event):
	if event.is_action_pressed("ui_cancel") and not is_resetting:
		toggle_pause()

func toggle_pause():
	"""Przełącza stan pauzy"""
	var paused = not get_tree().paused
	get_tree().paused = paused
	visible = paused
	
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_resume_button_pressed():
	"""Wznawia grę"""
	toggle_pause()

func _on_reset_button_pressed():
	"""Resetuje świat i gracza"""
	if is_resetting:
		print("Reset już w trakcie, czekaj...")
		return
	
	is_resetting = true
	get_tree().paused = false
	visible = false
	
	# Upewnij się, że mamy referencję do świata
	if world == null or not is_instance_valid(world):
		find_world()
	
	if world == null or not is_instance_valid(world):
		push_error("Nie można znaleźć świata do zresetowania!")
		is_resetting = false
		return
	
	# Znajdź gracza
	var players = get_tree().get_nodes_in_group("player")
	var player = players[0] if players.size() > 0 else null
	
	if not player or not is_instance_valid(player):
		push_error("Nie można znaleźć gracza!")
		is_resetting = false
		return
	
	print("=== ROZPOCZYNAM RESET ŚWIATA ===")
	
	# KROK 1: Zresetuj gracza (przed czyszczeniem świata)
	if player.has_method("respawn"):
		player.respawn()
		print("Gracz przeniesiony do spawn pointu")
	
	# KROK 2: Wyczyść i wygeneruj świat ponownie
	if world.has_method("generate_world_fast"):
		print("Generowanie nowego świata...")
		await world.generate_world_fast(100)
		print("Świat zresetowany pomyślnie!")
	
	# KROK 3: Poczekaj chwilę na stabilizację fizyki
	await get_tree().create_timer(0.1).timeout
	
	# KROK 4: Upewnij się że gracz jest na właściwej pozycji
	if player.has_method("respawn"):
		player.respawn()
	
	print("=== RESET ZAKOŃCZONY ===")
	is_resetting = false
	
	# Przywróć kontrolę myszy
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_quit_button_pressed():
	"""Zamyka grę"""
	print("=== ZAMYKANIE GRY ===")
	
	# Unpause gry
	get_tree().paused = false
	
	# Upewnij się że mamy referencję do świata
	if world == null or not is_instance_valid(world):
		find_world()
	
	# Wyczyść świat przed wyjściem (zapobiega crashom i memory leakom)
	if world and is_instance_valid(world) and world.has_method("clear_world"):
		print("Czyszczenie świata...")
		world.clear_world()
		
		# Poczekaj na zakończenie czyszczenia
		await get_tree().process_frame
		print("Świat wyczyszczony")
	
	# Zamknij grę
	print("Zamykanie aplikacji...")
	get_tree().quit()
