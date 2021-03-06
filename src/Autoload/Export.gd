extends Node

enum ExportTab { FRAME = 0, SPRITESHEET = 1, ANIMATION = 2 }
var current_tab : int = ExportTab.FRAME

# Frame options
var frame_number := 0

# All frames and their layers processed/blended into images
var processed_images = [] # Image[]

# Spritesheet options
var frame_current_tag := 0 # Export only current frame tag
var number_of_frames := 1
enum Orientation { ROWS = 0, COLUMNS = 1 }
var orientation : int = Orientation.ROWS
# How many rows/columns before new line is added
var lines_count := 1

# Animation options
enum AnimationType { MULTIPLE_FILES = 0, ANIMATED = 1 }
var animation_type : int = AnimationType.MULTIPLE_FILES
var background_color : Color = Color.white
enum AnimationDirection { FORWARD = 0, BACKWARDS = 1, PING_PONG = 2 }
var direction : int = AnimationDirection.FORWARD

# Options
var resize := 100
var interpolation := 0 # Image.Interpolation
var new_dir_for_each_frame_tag : bool = true # you don't need to store this after export

# Export directory path and export file name
var directory_path := ""
var file_name := "untitled"
var file_format : int = FileFormat.PNG
enum FileFormat { PNG = 0, GIF = 1}

# Store all settings after export, enables a quick re-export with same settings
var was_exported : bool = false
var exported_tab : int
var exported_frame_number : int
var exported_frame_current_tag : int
var exported_orientation : int
var exported_lines_count : int
var exported_animation_type : int
var exported_background_color : Color
var exported_direction : int
var exported_resize : int
var exported_interpolation : int
var exported_directory_path : String
var exported_file_name : String
var exported_file_format : int

# Export coroutine signal
var stop_export = false

var file_exists_alert = "File %s already exists. Overwrite?"


func process_frame() -> void:
	var frame = Global.current_project.frames[frame_number - 1]
	var image := Image.new()
	image.create(Global.current_project.size.x, Global.current_project.size.y, false, Image.FORMAT_RGBA8)
	blend_layers(image, frame)
	processed_images.clear()
	processed_images.append(image)


func process_spritesheet() -> void:
	# Range of frames determined by tags
	var frames := []
	if frame_current_tag > 0:
		var frame_start = Global.current_project.animation_tags[frame_current_tag - 1].from
		var frame_end = Global.current_project.animation_tags[frame_current_tag - 1].to
		frames = Global.current_project.frames.slice(frame_start-1, frame_end-1, 1, true)
	else:
		frames = Global.current_project.frames

	# Then store the size of frames for other functions
	number_of_frames = frames.size()

	# If rows mode selected calculate columns count and vice versa
	var spritesheet_columns = lines_count if orientation == Orientation.ROWS else frames_divided_by_spritesheet_lines()
	var spritesheet_rows = lines_count if orientation == Orientation.COLUMNS else frames_divided_by_spritesheet_lines()

	var width = Global.current_project.size.x * spritesheet_columns
	var height = Global.current_project.size.y * spritesheet_rows

	var whole_image := Image.new()
	whole_image.create(width, height, false, Image.FORMAT_RGBA8)
	whole_image.lock()
	var origin := Vector2.ZERO
	var hh := 0
	var vv := 0

	for frame in frames:
		if orientation == Orientation.ROWS:
			if vv < spritesheet_columns:
				origin.x = Global.current_project.size.x * vv
				vv += 1
			else:
				hh += 1
				origin.x = 0
				vv = 1
				origin.y = Global.current_project.size.y * hh
		else:
			if hh < spritesheet_rows:
				origin.y = Global.current_project.size.y * hh
				hh += 1
			else:
				vv += 1
				origin.y = 0
				hh = 1
				origin.x = Global.current_project.size.x * vv
		blend_layers(whole_image, frame, origin)

	processed_images.clear()
	processed_images.append(whole_image)


func process_animation() -> void:
	processed_images.clear()
	for frame in Global.current_project.frames:
		var image := Image.new()
		image.create(Global.current_project.size.x, Global.current_project.size.y, false, Image.FORMAT_RGBA8)
		blend_layers(image, frame)
		processed_images.append(image)


func export_processed_images(ignore_overwrites: bool, path_validation_alert_popup: AcceptDialog, file_exists_alert_popup: AcceptDialog, export_dialog: AcceptDialog ) -> bool:
	# Stop export if directory path or file name are not valid
	var dir = Directory.new()
	if not dir.dir_exists(directory_path) or not file_name.is_valid_filename():
		path_validation_alert_popup.popup_centered()
		return false

	# Check export paths
	var export_paths = []
	for i in range(processed_images.size()):
		stop_export = false
		var multiple_files := true if (current_tab == ExportTab.ANIMATION && animation_type == AnimationType.MULTIPLE_FILES) else false
		var export_path = create_export_path(multiple_files, i + 1)
		# If user want to create new directory for each animation tag then check if directories exist and create them if not
		if multiple_files and new_dir_for_each_frame_tag:
			var frame_tag_directory := Directory.new()
			if not frame_tag_directory.dir_exists(export_path.get_base_dir()):
				frame_tag_directory.open(directory_path)
				frame_tag_directory.make_dir(export_path.get_base_dir().get_file())
		# Check if the file already exists
		var fileCheck = File.new()
		if fileCheck.file_exists(export_path):
			# Ask user if he want's to overwrite the file
			if not was_exported or (was_exported and not ignore_overwrites):
				# Overwrite existing file?
				file_exists_alert_popup.dialog_text = file_exists_alert % export_path
				file_exists_alert_popup.popup_centered()
				# Stops the function until the user decides if he want's to overwrite
				yield(export_dialog, "resume_export_function")
				if stop_export:
					# User decided to stop export
					return
		export_paths.append(export_path)
		# Only get one export path if single file animated image is exported
		if current_tab == ExportTab.ANIMATION && animation_type == AnimationType.ANIMATED:
			break

	# Scale images that are to export
	scale_processed_images()

	if current_tab == ExportTab.ANIMATION && animation_type == AnimationType.ANIMATED:
		var frame_delay_in_ms = Global.animation_timer.wait_time * 100

		$GifExporter.begin_export(export_paths[0], processed_images[0].get_width(), processed_images[0].get_height(), frame_delay_in_ms, 0)
		match direction:
			AnimationDirection.FORWARD:
				for i in range(processed_images.size()):
					$GifExporter.write_frame(processed_images[i], background_color, frame_delay_in_ms)
			AnimationDirection.BACKWARDS:
				for i in range(processed_images.size() - 1, -1, -1):
					$GifExporter.write_frame(processed_images[i], background_color, frame_delay_in_ms)
			AnimationDirection.PING_PONG:
				for i in range(0, processed_images.size()):
					$GifExporter.write_frame(processed_images[i], background_color, frame_delay_in_ms)
				for i in range(processed_images.size() - 2, 0, -1):
					$GifExporter.write_frame(processed_images[i], background_color, frame_delay_in_ms)
		$GifExporter.end_export()
	else:
		for i in range(processed_images.size()):
			if OS.get_name() == "HTML5":
				Html5FileExchange.save_image(processed_images[i], export_paths[i].get_file())
			else:
				var err = processed_images[i].save_png(export_paths[i])
				if err != OK:
					OS.alert("Can't save file")

	# Store settings for quick export and when the dialog is opened again
	was_exported = true
	store_export_settings()
	Global.file_menu.get_popup().set_item_text(5, tr("Export") + " %s" % (file_name + file_format_string(file_format)))
	Global.notification_label("File(s) exported")
	return true


func scale_processed_images() -> void:
	for processed_image in processed_images:
		if resize != 100:
			processed_image.unlock()
			processed_image.resize(processed_image.get_size().x * resize / 100, processed_image.get_size().y * resize / 100, interpolation)


func file_format_string(format_enum : int) -> String:
	match format_enum:
		0: # PNG
			return '.png'
		1: # GIF
			return '.gif'
		_:
			return ''


func create_export_path(multifile: bool, frame: int = 0) -> String:
	var path = file_name
	# Only append frame number when there are multiple files exported
	if multifile:
		var frame_tag_and_start_id = get_proccessed_image_animation_tag_and_start_id(frame - 1)
		# Check if exported frame is in frame tag
		if frame_tag_and_start_id != null:
			var frame_tag = frame_tag_and_start_id[0]
			var start_id = frame_tag_and_start_id[1]
			# Remove unallowed characters in frame tag directory
			var regex := RegEx.new()
			regex.compile("[^a-zA-Z0-9_]+")
			var frame_tag_dir = regex.sub(frame_tag, "", true)
			if new_dir_for_each_frame_tag:
				# Add frame tag if frame has one
				# (frame - start_id + 1) Makes frames id to start from 1 in each frame tag directory
				path += "_" + frame_tag_dir + "_" + String(frame - start_id + 1)
				return directory_path.plus_file(frame_tag_dir).plus_file(path + file_format_string(file_format))
			else:
				# Add frame tag if frame has one
				# (frame - start_id + 1) Makes frames id to start from 1 in each frame tag
				path += "_" + frame_tag_dir + "_" + String(frame - start_id + 1)
		else:
			path += "_" + String(frame)

	return directory_path.plus_file(path + file_format_string(file_format))


func get_proccessed_image_animation_tag_and_start_id(processed_image_id : int) -> Array:
	var result_animation_tag_and_start_id = null
	for animation_tag in Global.current_project.animation_tags:
		# Check if processed image is in frame tag and assign frame tag and start id if yes
		# Then stop
		if (processed_image_id + 1) >= animation_tag.from and (processed_image_id + 1) <= animation_tag.to:
			result_animation_tag_and_start_id = [animation_tag.name, animation_tag.from]
			break
	return result_animation_tag_and_start_id


# Blends canvas layers into passed image starting from the origin position
func blend_layers(image : Image, frame : Frame, origin : Vector2 = Vector2(0, 0)) -> void:
	image.lock()
	var layer_i := 0
	for cel in frame.cels:
		if Global.current_project.layers[layer_i].visible:
			var cel_image := Image.new()
			cel_image.copy_from(cel.image)
			cel_image.lock()
			if cel.opacity < 1: # If we have cel transparency
				for xx in cel_image.get_size().x:
					for yy in cel_image.get_size().y:
						var pixel_color := cel_image.get_pixel(xx, yy)
						var alpha : float = pixel_color.a * cel.opacity
						cel_image.set_pixel(xx, yy, Color(pixel_color.r, pixel_color.g, pixel_color.b, alpha))
			image.blend_rect(cel_image, Rect2(Global.canvas.location, Global.current_project.size), origin)
		layer_i += 1
	image.unlock()


func frames_divided_by_spritesheet_lines() -> int:
	return int(ceil(number_of_frames / float(lines_count)))


func store_export_settings() -> void:
	exported_tab = current_tab
	exported_frame_number = frame_number
	exported_frame_current_tag = frame_current_tag
	exported_orientation = orientation
	exported_lines_count = lines_count
	exported_animation_type = animation_type
	exported_background_color = background_color
	exported_direction = direction
	exported_resize = resize
	exported_interpolation = interpolation
	exported_directory_path = directory_path
	exported_file_name = file_name
	exported_file_format = file_format


# Fill the dialog with previous export settings
func restore_previous_export_settings() -> void:
	current_tab = exported_tab
	frame_number = exported_frame_number if exported_frame_number <= Global.current_project.frames.size() else Global.current_project.frames.size()
	frame_current_tag = exported_frame_current_tag if exported_frame_current_tag <= Global.current_project.animation_tags.size() else 0
	orientation = exported_orientation
	lines_count = exported_lines_count
	animation_type = exported_animation_type
	background_color = exported_background_color
	direction = exported_direction
	resize = exported_resize
	interpolation = exported_interpolation
	directory_path = exported_directory_path
	file_name = exported_file_name
	file_format = exported_file_format

