extends VBoxContainer
class_name RandomWikipediaImage
## https://observablehq.com/@jleedev/random-wikimedia-image

const request_parameters: Dictionary = {
	"action": "query",
	"format": "json",
	"generator": "random",
	"grnnamespace": 0,          # Restricts search to main articles (not talk or help pages)
	"prop": "pageimages|extracts",
	"piprop": "original",       # Returns the URL of the original full-size image
	"exintro": true,            # Only return the introduction text before the first section
	"explaintext": true,        # Return plain text instead of HTML
	"redirects": 1
}

const api_url: String = "https://en.wikipedia.org/w/api.php"

const custom_headers: PackedStringArray = [
	"User-Agent: GodotWikiFrameGenerator/0.1 (Contact: everythingclacks@gmail.com)",
	"Content-Type: application/x-www-form-urlencoded"
]

@onready var page_requests: HTTPRequest = $PageRequests
@onready var image_requests: HTTPRequest = $ImageRequests
@onready var caption_label: Label = $Label
@onready var image_display: TextureRect = $Image

var image_request_url: String = ""

@export var retry_interval: float = 1.5

func _ready() -> void:
	page_requests.request_completed.connect(_http_request_completed)
	image_requests.request_completed.connect(_image_request_completed)
	set_random_image()

func construct_query_string(
		url: String,
		params: Dictionary = request_parameters
		) -> String:
	
	var query_string: String = ""
	for key in params:
		query_string += key + "=" + str(params[key]).uri_encode() + "&"
	
	return url + "?" + query_string

func set_random_image() -> void:
	var err: Error = page_requests.request(
		construct_query_string(api_url),
		custom_headers
	)
	if err == ERR_BUSY:
		push_warning("random image requested before page request finished, restarting page request")
		page_requests.cancel_request()
		set_random_image()
		return
	elif err == ERR_TIMEOUT:
		push_warning("page request timed out after five seconds, retrying...")
		page_requests.cancel_request()
		set_random_image()
		return
	elif err != OK:
		push_error("gulp: " + str(err))

func _http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code == 429:
		push_error("page request too many, trying again after 5 seconds")
		await get_tree().create_timer(5).timeout
		set_random_image()
		return
	elif response_code != 200: # where 200 = ok
		push_error("gulp; response code is: %d" % response_code)
		return
	
	var json_parser: JSON = JSON.new()
	var parsing_error: Error = json_parser.parse(body.get_string_from_utf8())
	if parsing_error != OK:
		push_error("gulp; json error %s" % parsing_error)
		return
	
	var response_dict: Dictionary = json_parser.get_data()
	var pages: Dictionary = response_dict.get("query", {}).get("pages", {})
	
	for page_id in pages.keys():
		var page_data = pages.get(page_id, {})
		if page_data == {}:
			push_warning("page with id %s couldn't be found, continuing" % page_id)
			await get_tree().create_timer(retry_interval).timeout
			continue
		
		var title = page_data.get("title", "")
		var extract: String = page_data.get("extract", "")
		if not page_data.has("original"):
			print("%s had no image, retrying . ." % title)
			set_random_image()
			return
		
		var image_url: String = page_data.get("original").get("source", "").split("?").get(0)
		var caption: String = ""
		if not extract.is_empty():
			caption = extract.split(".").get(0) + "."
		else:
			caption = "image from article %s." % title
		
		print("title: %s" % title)
		print("image url: %s" % image_url)
		print("caption: %s" % caption)
		image_request_url = image_url
		_set_visuals(image_url, caption)

func _set_visuals(image_url: String, caption: String) -> void:
	image_requests.request(
		image_url,
		custom_headers,
		HTTPClient.METHOD_GET
	)
	caption_label.set_text(caption)

func _image_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code == 429:
		push_error("image request too many, trying again after 5 seconds")
		await get_tree().create_timer(5).timeout
		image_requests.request(image_request_url, custom_headers)
		return
	elif response_code != 200:
		push_error("gulp; response code is: %d" % response_code)
		#if response_code == 429:
		#	await get_tree().create_timer(5).timeout
		#	image_requests.request(image_request_url)
		return
	
	var request_image: Image = Image.new()
	var load_error: Error
	
	var extension_check_url: String = image_request_url.to_lower()
	
	if extension_check_url.ends_with(".png"):
		load_error = request_image.load_png_from_buffer(body)
	elif extension_check_url.ends_with(".jpg") or extension_check_url.ends_with(".jpeg"):
		load_error = request_image.load_jpg_from_buffer(body)
	elif extension_check_url.ends_with(".webp"):
		load_error = request_image.load_webp_from_buffer(body)
	elif extension_check_url.ends_with(".svg"):
		load_error = request_image.load_svg_from_buffer(body)
	else:
		load_error = request_image.load_png_from_buffer(body)
	
	if load_error != OK:
		push_error("gulp; image error %s" % load_error)
		return
	
	image_display.texture = ImageTexture.create_from_image(request_image)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		set_random_image()
