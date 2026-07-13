class_name DebugLog
extends RefCounted

## Static class for handling debug logging functionality.
##
## This class provides methods to enable/disable debugging and log various game states
## without spamming the console. It uses color-coded rich text for better readability.

## Enables or disables debug mode.
static var debug_enabled: bool = true
static var visual_debug: bool = false # mouse cursor raycast, etc -- false by default (because visually invasive)

## Dictionary of color codes for different debug message types.
const DEBUG_COLORS: Dictionary = {
	"magenta": "FF00FF",
	"yellow": "FFFF00",
	"green": "00FF00",
	"cyan": "00FFFF",
	"purple": "800080",
	"orange": "FFA500",
	"red": "FF0000"
}

## Dictionary to store temporary and old values for various debug states.
static var debug_dict: Dictionary = {
	"participant_turn": {
		"tmp": null, "old": null,
		"message": "[ --- Turn Update --- ] 👾 Switched participant: ", 
		"color": "magenta",
		"type": "bool",
		"bool_strings": ["Player", "Opponent"]
		},
	"read_file": {
		"tmp": null, "old": null,
		"message": "[ --- Read File--- ] Read File ", 
		"color": "red",
		"type": "bool",
		"bool_strings": ["Succeed", "Fail"]
		},
	"func_call": {
		"tmp": null, "old": null,
		"message": "[ --- Func Call--- ] ", 
		"color": "yellow",
		"type": "concat1"
		},
	"update_visual": {
		"tmp": null, "old": null,
		"message": "[ --- Update Visual--- ] ", 
		"color": "orange",
		"type": "concat1"
		},
	"position_debug": {
		"tmp": null, "old": null,
		"message": "[ --- Position--- ] ", 
		"color": "cyan",
		"type": "concat1"
		},
	"combat_info": {
		"tmp": null, "old": null,
		"message": "[ --- Combat Info--- ] ", 
		"color": "purple",
		"type": "concat1"
		},
	"attack": {
		"tmp": null, "old": null,
		"message": "[ --- Attack Info--- ] ", 
		"color": "red",
		"type": "concat1"
		},
	"hit_roll": {
		"tmp": null, "old": null,
		"message": "[ --- Hit Roll--- ] ", 
		"color": "red",
		"type": "concat1"
		},
}

## Enables or disables debug logging.
##
## @param enabled: Boolean value to enable (true) or disable (false) debug logging.
static func set_debug_enabled(enabled: bool) -> void:
	debug_enabled = enabled


## Logs debug messages without spamming the console.
##
## This function checks if the debug state has changed before logging,
## preventing repeated messages for unchanged states.
##
## @param debug_name: The name of the debug state to update.
## @param argument: The new value of the debug state.
static func debug_nospam(debug_name: String, argument: Variant) -> void:
	if not debug_enabled:
		return
	
	if debug_name in debug_dict:
		var _d: Dictionary = debug_dict[debug_name]
		
		match _d.type:
			"bool":
				debug_log_bool(_d, argument)
			"concat1":
				debug_log_concat1(_d, argument)


static func debug_log_bool(dict_entry: Dictionary, argument: Variant) -> void:
	dict_entry.tmp = argument
	
	if dict_entry.old != dict_entry.tmp:
		var open_color: String = "[color=#" + DEBUG_COLORS[dict_entry.color] + "]"
		var close_color: String = "[/color]"
		
		var parse_bool: String = dict_entry.bool_strings[0] if argument else dict_entry.bool_strings[1]
		
		if dict_entry.has('message'): # todo: got a crash 'cause no dict_entry.message
			print_rich(open_color, dict_entry.message, "[i][u]", parse_bool, "[/u][/i]", close_color) # Print color-coded message
		
	if dict_entry.old == null or dict_entry.old != dict_entry.tmp:
		dict_entry.old = dict_entry.tmp # Update old value if it's null or different from tmp


static func debug_log_concat1(dict_entry: Dictionary, argument: Variant) -> void:
	dict_entry.tmp = argument
	
	if dict_entry.old != dict_entry.tmp:
		var open_color: String = "[color=#" + DEBUG_COLORS[dict_entry.color] + "]"
		var close_color: String = "[/color]"
		
		if dict_entry.has('message'): # todo: got a crash 'cause no dict_entry.message
			print_rich(open_color, dict_entry.message, "[i][u]", dict_entry.tmp, "[/u][/i]", close_color) # Print color-coded message
		
	if dict_entry.old == null or dict_entry.old != dict_entry.tmp:
		dict_entry.old = dict_entry.tmp # Update old value if it's null or different from tmp
