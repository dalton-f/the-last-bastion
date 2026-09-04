@tool
extends EditorPlugin

#region Constants
const PLUGIN_DIRECTORY_PATH: String = "res://addons/kaykit_import_helper/"
const PLUGIN_DOCK_SCENE_PATH: String = PLUGIN_DIRECTORY_PATH + "advanced_importer_dock/advanced_importer_dock.tscn"

const AVAILABLE_DOCK_LAYOUTS: int = EditorDock.DockLayout.DOCK_LAYOUT_VERTICAL | EditorDock.DockLayout.DOCK_LAYOUT_FLOATING
const DEFAULT_DOCK_SLOT: EditorDock.DockSlot = EditorDock.DockSlot.DOCK_SLOT_LEFT_UR
const DEFAULT_DOCK_TITLE: String = "Advanced Import"

const BASE_OUTPUT_DIRECTORY_PATH: String = "res://assets/"
const MATERIALS_OUTPUT_DIRECTORY_PATH: String = BASE_OUTPUT_DIRECTORY_PATH + "materials/"
const TEXTURES_OUTPUT_DIRECTORY_PATH: String = BASE_OUTPUT_DIRECTORY_PATH + "textures/"
const MODELS_OUTPUT_DIRECTORY_PATH: String = BASE_OUTPUT_DIRECTORY_PATH + "models/"
const MESH_LIBS_OUTPUT_DIRECTORY_PATH: String = BASE_OUTPUT_DIRECTORY_PATH + "mesh_libs/"

const SELECTED_FILES_DEFAULT_TEXT: String = "[color=WEB_GRAY]No Selected File / Directory[/color]"
#endregion

#region Variables
# A class member to hold the dock during the plugin life cycle.
var dock
# A class member to hold the instantiated dock scene during the plugin life cycle.
var dock_scene

var extracted_materials: Dictionary = {}
#endregion

#region Virtual Methods
# Initialization of the plugin goes here.
func _enter_tree():
	_build_dock()
	
	_connect_signals()

# Clean-up of the plugin goes here.
func _exit_tree():
	_disconnect_signals()
		
	_erase_dock()
#endregion

#region Plugin Lifecycle
func _build_dock() -> void:
	# Load the dock scene and instantiate it.
	dock_scene = preload(PLUGIN_DOCK_SCENE_PATH).instantiate()

	# Create the dock and add the loaded scene to it.
	dock = EditorDock.new()
	dock.add_child(dock_scene)

	dock.title = DEFAULT_DOCK_TITLE

	# Note that LEFT_UR means the left of the editor, upper-right dock.
	dock.default_slot = DEFAULT_DOCK_SLOT

	# Allow the dock to be on the left or right of the editor, and to be made floating.
	dock.available_layouts = AVAILABLE_DOCK_LAYOUTS

	add_dock(dock)
	
	print_rich("[color=green][b][KayKit Import Helper][/b] Dock initialized successfully[/color]")

func _erase_dock() -> void:
	# Remove the dock.
	remove_dock(dock)
	# Erase the control from the memory.
	dock.queue_free()
	
	print_rich("[color=green][b][KayKit Import Helper][/b] Dock erased successfully[/color]")

func _connect_signals() -> void:
	dock_scene.connect("reimport_requested", _handle_reimport_request)
	
	EditorInterface.get_file_system_dock().connect("selection_changed", _update_dock_state)
	
	print_rich("[color=green][b][KayKit Import Helper][/b] Signals connected successfully[/color]")

func _disconnect_signals() -> void:
	dock_scene.disconnect("reimport_requested", _handle_reimport_request)
	
	EditorInterface.get_file_system_dock().disconnect("selection_changed", _update_dock_state)
	
	print_rich("[color=green][b][KayKit Import Helper][/b] Signals disconnected successfully[/color]")

# Updates the dock UI based on currently selected folders and their valid files
func _update_dock_state() -> void:
	# Get all selected folder paths
	var selected_folder_paths: Array = _get_selected_folders()
	
	# If no folders are selected, reset the dock and exit early
	if selected_folder_paths.is_empty():
		_reset_dock_state()
		return
	
	# This will store all valid files found in selected folders
	var selected_file_paths: Array = []
	
	# Loop through each selected folder
	for selected_folder_path: String in selected_folder_paths:
		# Get files with allowed extensions (png and gltf)
		var valid_file_paths: Array = _get_files(selected_folder_path, ["png", "gltf"])
		
		# Add those files to the main list
		selected_file_paths.append_array(valid_file_paths)
	
	# If no valid files were found, reset the dock and exit early
	if selected_file_paths.is_empty():
		_reset_dock_state()
		return
	
	# Create a separator for displaying files (newline + bullet point)
	var file_display_seperator: String = "\n%c " % [8226]
	
	# Update the UI label with:
	# - number of selected files
	# - correct singular/plural wording
	# - formatted list of file paths
	dock_scene.selected_files_rich_text_label.text = "[b]%d[/b] %s:%s%s" % [
		selected_file_paths.size(),
		"Selected File" if selected_file_paths.size() == 1 else "Selected Files",
		file_display_seperator,
		file_display_seperator.join(selected_file_paths)
	]
	
	# Enable the reimport button since there are some valid files
	dock_scene.reimport_button.disabled = false
	
# Resets the dock UI to its default state
func _reset_dock_state() -> void:
	# Disable the reimport button since there are no valid files
	dock_scene.reimport_button.disabled = true
	# Reset the label text to its default placeholder
	dock_scene.selected_files_rich_text_label.text = SELECTED_FILES_DEFAULT_TEXT
#endregion

func _handle_reimport_request(settings: Dictionary[String, bool]) -> void:
	print_rich("[color=green][b][KayKit Import Helper][/b] Reimport requested with settings: %s [/color]" % settings)

	var selected_folder_paths: Array[String] = _get_selected_folders()

	# Build the output directories if they don't already exist
	await _build_output_directories(selected_folder_paths)
	
	# Loop over each selected folder to process them individually
	for selected_folder_path in selected_folder_paths:
		var pack_name: String = selected_folder_path.trim_suffix("/").get_file() + "/"
		
		var texture_paths: Array = _get_files(selected_folder_path, ["png"])
		var model_paths: Array = _get_files(selected_folder_path, ["gltf"])
	
		# Skip the full folder if it only includes valid texture paths or valid model paths instead of both
		if texture_paths.is_empty() or model_paths.is_empty():
			push_warning("[KayKit Import Helper] Skipped (missing textures or models): %s[/color]" % selected_folder_path)
			continue
		
		print_rich("\n[color=green][b][KayKit Import Helper][/b] --- Extracting Materials ---[/color]\n")
		_extract_materials(model_paths, pack_name)

		print_rich("\n[color=green][b][KayKit Import Helper][/b] --- Replacing Materials ---[/color]\n")
		await _replace_materials(model_paths)
		
		print_rich("\n[color=green][b][KayKit Import Helper][/b] --- Moving Textures ---[/color]\n")
		await _move_textures(texture_paths, pack_name)
		
		print_rich("\n[color=green][b][KayKit Import Helper][/b] --- Fixing GLTF Texture URIs ---[/color]\n")
		_fix_gltf_texture_uris(model_paths, pack_name)
		
		print_rich("\n[color=green][b][KayKit Import Helper][/b] --- Moving Models ---[/color]\n")
		_move_models(model_paths, pack_name)
		
		if settings.generate_gridmap:
			print_rich("\n[color=green][b][KayKit Import Helper][/b] --- Gridmap Generation ---[/color]\n")
			_generate_gridmap_resources(pack_name)
		
		print_rich("\n[color=green][b][KayKit Import Helper][/b] --- Fixing Texture Compression Modes ---[/color]\n")
		_fix_texture_compression_modes(pack_name)
		
		# Remove the selected folder path (cleans up filesystem after processing files)
		DirAccess.remove_absolute(selected_folder_path)
			
	await _refresh_filesystem()
		
	print_rich("\n[color=green][b][KayKit Import Helper][/b] Reimport successfully completed with settings: %s [/color]" % settings)

# Creates output directory structure for selected asset folders.
func _build_output_directories(selected_folder_paths: Array[String]) -> void:
	var base_directories = [
		MATERIALS_OUTPUT_DIRECTORY_PATH,
		TEXTURES_OUTPUT_DIRECTORY_PATH,
		MODELS_OUTPUT_DIRECTORY_PATH,
		MESH_LIBS_OUTPUT_DIRECTORY_PATH
	]

	# Loop through each base directory
	for base_dir in base_directories:
		# Loop through each selected folder path
		for folder_path in selected_folder_paths:
			# Extract the folder name (used as pack name)
			var pack_name: String = folder_path.trim_suffix("/").get_file()
			# Build the full subdirectory path (e.g. materials/pack_name)
			var sub_dir: String = base_dir.path_join(pack_name)
			
			# Create the directory if it doesn't exist
			_make_dir(sub_dir)
			
	# Refresh the filesystem so the editor recognizes new folders
	await _refresh_filesystem()
	
	print_rich("[color=green][b][KayKit Import Helper][/b] Built output directories successfully [/color]")

# Extracts materials from a list of model files.
# For each path provided, it processes the file and stores
# any found materials into the `extracted_materials` dictionary.
func _extract_materials(model_paths: Array, pack_name: String) -> void:
	# Reset previously stored materials
	extracted_materials.clear() 
	
	# Loop through all model paths by index
	for idx: int in model_paths.size():
		var model_path: String = model_paths[idx]
		
		# Extract materials from the current file
		_extract_materials_from_file(model_path, pack_name)
		
		# Log progress with current index and total count
		print_rich("[color=green][b][KayKit Import Helper][/b] [%d/%d] Successfully extracted materials from %s [/color]" % [idx + 1, model_paths.size(), model_path])

# Replaces materials in a list of model files.
# After processing each file, it refreshes the filesystem and reimports assets.
func _replace_materials(model_paths: Array) -> void:
	# Loop through all model paths by index
	for idx: int in model_paths.size():
		var model_path: String = model_paths[idx]
		
		# Replace materials in the current file
		_replace_materials_from_file(model_path)
		
		# Wait for filesystem refresh and reimport to complete
		await _refresh_filesystem_and_imports()
		
		# Log progress
		print_rich("[color=green][b][KayKit Import Helper][/b] [%d/%d] Successfully replaced materials of %s [/color]" % [idx + 1, model_paths.size(), model_path])

# Moves texture files and their corresponding .import files
func _move_textures(texture_paths: Array, pack_name: String) -> void:
	await _move_files(texture_paths, TEXTURES_OUTPUT_DIRECTORY_PATH.path_join(pack_name), true)

func _fix_gltf_texture_uris(model_paths: Array, pack_name: String) -> void:
	for idx: int in model_paths.size():
		var model_path: String = model_paths[idx]
		
		# Open file for reading
		var file: FileAccess = FileAccess.open(model_path, FileAccess.READ)
		
		# If file can't be opened, log error and skip to next file
		if file == null:
			push_error("[KayKit Import Helper] Failed to open file %s" % model_path)
			continue
			
		# Read entire file as text
		var content: String = file.get_as_text()
		file.close()
			
		# Parse JSON content
		var json: Variant = JSON.parse_string(content)
			
		# Ensure parsed data is a dictionary
		if typeof(json) != TYPE_DICTIONARY:
			push_error("[KayKit Import Helper] File %s has invalid JSON contents" % model_path)
			continue
			
		if json.has("images"):
			for img in json["images"]:
				if img.has("uri"):
					var filename = img["uri"].get_file()
					# Rebuild the image path to point to the correct texture within the selected asset pack
					img["uri"] = "../../textures/" + pack_name + filename
			
		# Convert modified JSON back to formatted string        
		var new_text: String = JSON.stringify(json, "\t")
		# Open file for writing (overwrite existing content)
		var out: FileAccess = FileAccess.open(model_path, FileAccess.WRITE)
			
		# If file can't be opened for writing, log error and skip
		if out == null:
			push_error("[KayKit Import Helper] Failed to write file %s" % model_path)
			continue
		
		# Save updated JSON back to file
		out.store_string(new_text)
		out.close()
		
		print_rich("[color=green][b][KayKit Import Helper][/b] [%d/%d] Successfully updated gltf uris of %s[/color]" % [idx + 1, model_paths.size(), model_path])

# Moves texture files and their corresponding .import and .bin files
func _move_models(model_paths: Array, pack_name: String) -> void:
	# _move_files has three booleans, include .import (true), include .bin (true) and trigger filesystem refresh (false)
	_move_files(model_paths, MODELS_OUTPUT_DIRECTORY_PATH.path_join(pack_name), true, true, false)

func _generate_gridmap_resources(pack_name: String) -> void:
	var new_model_paths = _get_files(MODELS_OUTPUT_DIRECTORY_PATH.path_join(pack_name), ["gltf"])
	
	# Ensure that the placement of the models is in an equal square grid depending on the amount of assets
	var model_count = new_model_paths.size()
	var columns: int = int(ceil(sqrt(model_count)))
	var rows: int = int(ceil(model_count / float(columns)))
	
	var spacing: float = 8.0
	
	# Generate the root node for a scene
	var root := Node3D.new()
	root.name = pack_name.trim_suffix("/").to_pascal_case()
	
	for idx: int in model_count:
		var model_path: String = new_model_paths[idx]
		var scene: Resource = load(model_path)
		
		if scene == null:
			push_error("[KayKit Import Helper] Failed to load: %s" % model_path)
			continue
			
		if not scene is PackedScene:
			push_error("[KayKit Import Helper] Not a PackedScene: %s" % model_path)
			continue
			
		var instance = scene.instantiate()
			
		if instance == null:
			push_error("[KayKit Import Helper] Failed to instantiate: %s" % model_path)
			continue
		
		instance.name = "Instance_%d" % idx
			
		root.add_child(instance)
		instance.owner = root
			
		var child = instance.get_child(0)

		# Detach child from instance
		instance.remove_child(child)
		child.owner = null

		# Add child directly to your root
		root.add_child(child)
		child.owner = root
		
		# TODO: Could be made recursive, but for now ensure that any grandchildren get added correctly
		for grandchild in child.get_children():
			grandchild.owner = root
			grandchild.name = grandchild.name.to_pascal_case()
		
		var x = idx % columns
		var z = idx / columns
		
		# Position each child into the grid correctly
		child.position = Vector3(x * spacing, 0, z * spacing)
		# Fix naming conventions
		child.name = child.name.to_pascal_case()
		
		# Generate collisions
		child.create_trimesh_collision()
		
		for grandchild in child.get_children():
			if grandchild is MeshInstance3D:
				grandchild.create_trimesh_collision()
		
		# Remove the original root node
		instance.owner = null
		instance.queue_free()
		
		print_rich("[color=green][b][KayKit Import Helper][/b] [%d/%d] Successfully placed %s into a scene [/color]" % [idx + 1, new_model_paths.size(), model_path])
	
	# Pack the placed nodes into a proper scene
	var packed := PackedScene.new()
	packed.pack(root)
	
	# Save the packed scene
	var clean_pack_name = pack_name.trim_suffix("/")
	var save_path: String = MESH_LIBS_OUTPUT_DIRECTORY_PATH.path_join(pack_name) + clean_pack_name + ".tscn"
	ResourceSaver.save(packed, save_path)

func _fix_texture_compression_modes(pack_name: String) -> void:
	var new_texture_paths = _get_files(TEXTURES_OUTPUT_DIRECTORY_PATH.path_join(pack_name), ["png"])
	
	for idx: int in new_texture_paths.size():
		var new_texture_path: String = new_texture_paths[idx]
		var import_path: String = "%s.import" % [new_texture_path]
		var import_file: ConfigFile = _open_import_file(import_path)
		
		# Ensure all textures get set to lossless compression to prevent banding
		import_file.set_value("params", "compress/mode", 0)
		import_file.save(import_path)
	
		print_rich("[color=green][b][KayKit Import Helper][/b] [%d/%d] Successfully updated compression mode of %s[/color]" % [idx + 1, new_texture_paths.size(), new_texture_path])

#region Material Extraction & Replacement
# Extracts all materials from meshes in a scene file and saves them as external resources.
func _extract_materials_from_file(file_path: String, pack_name: String) -> void:
	# Get all MeshInstance3D nodes from the scene
	var mesh_instance_list: Array[MeshInstance3D] = _get_mesh_instances_from_scene(file_path)

	# If no meshes were found, log an error and stop
	if mesh_instance_list.size() == 0:
		push_error("[KayKit Import Helper] Failed to find any mesh instances in %s" % file_path)
		return

	# Iterate through each mesh instance
	for mesh_instance: MeshInstance3D in mesh_instance_list:
		var mesh: Mesh = mesh_instance.mesh

		# Skip if mesh is invalid
		if !is_instance_valid(mesh):
			continue

		# Loop through all surfaces of the mesh
		for idx: int in range(mesh.get_surface_count()):
			# Duplicate the material so we don't modify the original
			var material: Material = mesh.surface_get_material(idx).duplicate(true) as Material

			if !is_instance_valid(material):
				material = null
				continue
			
			# If this material hasn't been processed yet
			if !extracted_materials.has(material.resource_name):
				var material_path: String = "%s%s.tres" % [MATERIALS_OUTPUT_DIRECTORY_PATH.path_join(pack_name), material.resource_name.to_snake_case()]
				
				# Save the material only if it doesn't already exist
				if !FileAccess.file_exists(material_path):
					ResourceSaver.save(material, material_path)
			
				# Updated processed materials 
				# Store the material name and its saved path
				extracted_materials[material.resource_name] = material_path

			material = null

# Loads a scene file and returns all MeshInstance3D nodes found within it.
func _get_mesh_instances_from_scene(file_path: String) -> Array[MeshInstance3D]:
	# Load the scene without using cache (ensures fresh data)
	var packed_scene: PackedScene = ResourceLoader.load(
		file_path,
		"",
		ResourceLoader.CacheMode.CACHE_MODE_IGNORE_DEEP,
	) as PackedScene

	# Return empty array if scene failed to load
	if !is_instance_valid(packed_scene):
		return []

	# Instantiate the scene into a node tree
	var node_instance: Node = packed_scene.instantiate()

	# Return empty array if instantiation failed
	if !is_instance_valid(node_instance):
		return []

	var mesh_list: Array[MeshInstance3D] = []

	# Recursively find all MeshInstance3D nodes in the scene
	for node: Node in node_instance.find_children("*", "MeshInstance3D", true, true):
		if node is MeshInstance3D:
			mesh_list.append(node as MeshInstance3D)

	return mesh_list

# Updates a .import file to replace embedded materials with external ones.
# Uses previously extracted materials and assigns them via subresource settings.
func _replace_materials_from_file(file_path: String) -> void:
	var import_path: String = "%s.import" % [file_path]
	var import_file: ConfigFile = _open_import_file(import_path)

	# Retrieve existing subresource data (or create empty dictionary)
	var subresources: Dictionary = import_file.get_value(
		"params",
		"_subresources",
		{ },
	) as Dictionary

	if !subresources.has("materials"):
		subresources["materials"] = { }

	# Loop through all extracted materials
	for material_name: String in extracted_materials.keys() as Array[String]:
		# Assign each material to use an external resource path
		subresources["materials"][material_name] = {
			"use_external/enabled": true,
			"use_external/path": extracted_materials[material_name],
		}

	# Save updated subresource configuration back into the import file
	import_file.set_value("params", "_subresources", subresources)
	import_file.save(import_path)
#endregion

#region Utility Functions
# Refreshes the Godot editor filesystem
# Waits until scanning is fully complete before continuing
func _refresh_filesystem() -> void:
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	
	# Start scanning the filesystem
	fs.scan() 
		
	# Wait until scanning finishes
	while fs.is_scanning():
		await fs.filesystem_changed
		
	# Wait one frame to ensure updates are applied
	await get_tree().process_frame

# Refreshes both source imports (e.g. textures, models) and filesystem
func _refresh_filesystem_and_imports() -> void:
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	
	# Scan source files (triggers reimport if needed)
	fs.scan_sources() 
	
	# Wait until source scanning finishes
	while fs.is_scanning():
		await fs.sources_changed
	
	# Wait one frame to ensure updates are applied
	await get_tree().process_frame
	
	# Then refresh full filesystem
	fs.scan()
	
	# Wait until filesystem scanning finishes
	while fs.is_scanning():
		await fs.filesystem_changed
		
	# Wait one frame to ensure updates are applied	
	await get_tree().process_frame

# Returns only selected paths that are valid folders
func _get_selected_folders() -> Array[String]:
	var folders: Array[String] = []
	
	var selected_paths: PackedStringArray = EditorInterface.get_selected_paths()
	
	for path: String in selected_paths:
		# Check if the selected path is a directory
		if DirAccess.dir_exists_absolute(path):
			folders.append(path)
	
	return folders

# Opens a .import file (ConfigFile format) and returns it
# Returns null if loading fails
func _open_import_file(import_file_path: String) -> ConfigFile:
	var import_file: ConfigFile = ConfigFile.new()
	var error: Error = import_file.load(import_file_path)

	# Handle loading failure
	if error != Error.OK:
		push_error("[KayKit Import Helper] Failed to open import file: %s" % import_file_path)
		return null

	return import_file

# Recursively collects files from a directory
# - extensions: optional filter (e.g. ["png", "jpg"])
# - scan_subfolders: whether to include subdirectories (currently always scans)
func _get_files(directory_path: String, extensions: Array = [], scan_subfolders: bool = false) -> Array:
	var results: Array = []
	
	var directory: DirAccess = DirAccess.open(directory_path)
	
	# If directory can't be opened, return empty list
	if directory == null:
		push_error("[KayKit Import Helper] Failed to open directory: %s" % directory_path)
		return results
		
	# Initalize the stream used to list all files and folders using get_next()
	directory.list_dir_begin()
		
	var file_name: String = directory.get_next()
		
	while file_name != "":
		# Skip any hidden files or folders
		if file_name.begins_with("."):
			file_name = directory.get_next()
			continue
				
		var full_path = directory_path.path_join(file_name)
			
		# If it's a directory, recurse into it
		if directory.current_is_dir():
			var subfolder_results: Array = _get_files(full_path, extensions, scan_subfolders)
			results.append_array(subfolder_results)
		else:
			# Add file if it matches extensions or no filter is set
			if extensions.is_empty() or file_name.get_extension() in extensions:
				results.append(full_path)
				
		file_name = directory.get_next()
	
	# Close the stream
	directory.list_dir_end()

	return results

# Makes a directory if it doesn't already exist
func _make_dir(path: String) -> void:
	# If directory already exists, do nothing
	if DirAccess.dir_exists_absolute(path):
		return

	var err := DirAccess.make_dir_recursive_absolute(path)

	if err != OK:
		push_error("[KayKit Import Helper] Failed to create directory: %s" % path)
		return 

func _move_files(file_paths: Array, target_dir: String, move_import: bool = false, move_bin: bool = false, trigger_filesystem_refresh: bool = true) -> void:
	for idx in file_paths.size():
		var file_path: String = file_paths[idx]
		
		if not FileAccess.file_exists(file_path):
			push_warning("[KayKit Import Helper] File does not exist: %s" % file_path)
			continue

		var file_name = file_path.get_file()

		var new_file_path: String = target_dir.path_join(file_name)

		# Move main file
		var err: Error = DirAccess.rename_absolute(file_path, new_file_path)
		
		if err != Error.OK:
			push_error("[KayKit Import Helper] Failed to move file: %s → %s" % [file_path, new_file_path])
			continue

		# Optionally move .bin file for .gtlfs
		if move_bin:
			var bin_path: String = file_path.replace(".gltf", ".bin")
			
			if FileAccess.file_exists(bin_path):
				var new_bin_path: String = target_dir.path_join(bin_path.get_file())
				var bin_err: Error = DirAccess.rename_absolute(bin_path, new_bin_path)
				
				if bin_err != Error.OK:
					push_warning("[KayKit Import Helper] Failed to move bin file: %s" % bin_path)
			
		# Optionally move .import file (Godot-specific)
		if move_import:
			var import_path: String = "%s.import" % [file_path]
			
			if FileAccess.file_exists(import_path):
				var new_import_path: String = target_dir.path_join(import_path.get_file())
				var import_err: Error = DirAccess.rename_absolute(import_path, new_import_path)
				
				if import_err != Error.OK:
					push_warning("[KayKit Import Helper] Failed to move import file: %s" % import_path)
		
		if trigger_filesystem_refresh:
			# Refresh filesystem so Godot detects moved assets
			await _refresh_filesystem()
		
		print_rich("[color=green][b][KayKit Import Helper][/b] [%d/%d] Successfully moved file %s → %s[/color]" % [idx + 1, file_paths.size(), file_path, new_file_path])
#endregion
