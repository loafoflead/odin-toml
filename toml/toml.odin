package toml

/*
	Toml v1.0.0, in Odin (of course). Link: https://toml.io/en/v1.0.0

	Author: loafoflead (keith.shale680@passinbox.com)
*/

import "base:runtime"

import "core:time/datetime"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:slice"
import "core:unicode"
import "core:unicode/utf8"

import "core:log"
import "core:fmt"

Toml_Array :: []Toml_Value
Toml_Map :: map[Toml_Key]Toml_Value

Toml_Value :: union {
	string,
	int,
	f64,
	bool,
	// TODO: Support date offsets ( I dont understand how Odin does this :[ )
	// theres a book https://pkg.odin-lang.org/core/time/datetime/#Time, 
	// https://github.com/odin-lang/Odin/blob/9b4c0ea4920ea70b3e9206979aa7fd36608c4837/core/time/datetime/datetime.odin#L4
	datetime.DateTime,
	datetime.Time,
	Toml_Array,
	Toml_Map,
}

Toml_Value_Type :: enum {
	String,
	Int,
	Float,
	Bool,
	Date_Time,
	Time,
	Array,
	Map, // table (gable (mabel (fable (payable?))))
}

Toml_Key :: distinct string

Toml_Parse_Error :: enum {
	None,
	Failed_To_Read,
}

Toml_Error :: union #no_nil {
	Toml_Parse_Error,
	os.Error,
}

Toml_File :: struct {
	super_table: Toml_Map,
}

runes_to_key :: proc(s: []rune, allocator: runtime.Allocator) -> Toml_Key {
	return Toml_Key(utf8.runes_to_string(s, allocator))
}

panicl :: proc(path: string, line, column: int, args: ..any) -> ! {
	loc := fmt.tprintf("%s(%i:%i):", path, line, column)
	log.panic(loc, args)
}

// Parses a TOML document from a filepath. It takes two allocator parameters, one for intermediate
// allocations and one that is used for the final data structure.
parse_from_filepath :: proc(path: string, data_allocator := context.allocator, temp_allocator := context.temp_allocator) -> (result: Toml_File, err: Toml_Error) {
	data, ok := os.read_entire_file(path, temp_allocator)
	if !ok do return {}, .Failed_To_Read

	content := string(data)
	content_runes := utf8.string_to_runes(content, temp_allocator)
	if len(content) == 0 do err = .None
	// lines := strings.split_lines(content, allocator)

	result.super_table = make(Toml_Map, data_allocator)

	line, column, i, ir := 1, 1, 0, 0

	skip_line := false

	LARGEST_KEY::64

	key_buffer: [LARGEST_KEY]rune
	key_len: int

	value_type: Maybe(Toml_Value_Type)
	value_buffer: [dynamic]u8 = make([dynamic]u8, temp_allocator)

	// string
	escaping: bool
	// end-string

	for i < len(content) {
		c := content[i]
		// log.infof("%c", c)
		// insane that this literally solves a problem i constantly have
		// defer in Odin is the best there is and the best thing in the omniverse (probably)
		defer {
			column += 1
			i += 1
			ir += 1
		}

		if skip_line && c != '\n' do continue

		if key_len == 0 {
			switch c {
			case '#':
				skip_line = true
			case '\n':
				line += 1
				column = 1
				skip_line = false
			case '"':
				unimplemented("Declaration of a quoted key")
			case '[':
				unimplemented("Declaration of a table")
			case ' ', '\t', '\r':
				continue
			case:
				// keys can have unicode in them, so we need runes
				for r, i in content[i:] {
					if unicode.is_white_space(r) || r == '=' do break
					if i > len(key_buffer)-1 do panicl(path, line, column, "Key must (for now) be less than", len(key_buffer), "runes.")

					key_buffer[i] = r
					key_len = i+1
				}
				// TODO: i bet this will be the source of an error, mark my words
				i += key_len		
			}
		}
		else { // key found
			if type, ok := value_type.?; ok {
				switch type {
				case .String:
					if c == '\\' {
						escaping = true
					}
					else if c == '"' {
						if !escaping {
							value_type = nil
							// TODO: dont do this pointless back & forth |b| runes & string
							result.super_table[runes_to_key(key_buffer[:key_len], data_allocator)] = string(value_buffer[:])
							clear(&value_buffer)
							key_len = 0
							continue
						}
					}
					if escaping {
						switch c {
						case '"': append(&value_buffer, '"')
						case 'n': append(&value_buffer, '\n')
						case 't': append(&value_buffer, '\t')
						case:
							unimplemented(fmt.tprintf("Escape '\\%s'", c))
						}
						// TODO: are there any multi-line escapes?
						escaping = false
					}
					else {
						append(&value_buffer, c)
					}
				case .Bool, .Int, .Float, .Date_Time, .Time, .Array, .Map:
					unimplemented(fmt.tprintf("Parse value of type %v", type))
				}
			}
			else { // no type determined yet
				switch c {
				case '#':
					panicl(path, line, column, "Declarations must be of the form key = value, unexpected comment found")
				case '\n':
					panicl(path, line, column, "Declarations must be on the same line")
				case '"':
					value_type = .String
				case '\'':
					unimplemented("Literal string values")
				case '+','-':
					unimplemented("Leading signs for number types")
				case '[':
					value_type = .Array
				case '{':
					value_type = .Map
				case ' ', '\t', '\r':
					continue
				case:
					// .......\n.......
					// newline^
					//		  v
					// [..][..][..][..]

					newline := strings.index(content[i:], "\n")
					value := content[i:i+newline]
					c, _idk_what_this_is := utf8.decode_rune_in_bytes(transmute([]u8)value[0:1])
					// log.infof("-------> %c, %v, %v", c, result, key_buffer)

					if unicode.is_number(c) {
						// you can't keep using string.contains without finding out
						// how to use one call to see if any of the characters in the 
						// string are prese---
						// I DID IT BECAUSE I LIKED IT
						// no---
						// AND I'D DO IT AGAIN IF I HAD THE CHANCE!!!!!
						if strings.contains(value, ":") || strings.contains(value, "-") {
							unimplemented("datetime or time")
						}
						else if strings.contains(value, ".") {
							double, ok := strconv.parse_f64(value)
							if !ok do panicl(path, line, column, "Expected a float but could not parse", value)
							value_type = nil
							// TODO: dont do this pointless back & forth |b| runes & string
							result.super_table[runes_to_key(key_buffer[:key_len], data_allocator)] = double
							clear(&value_buffer)
							key_len = 0
							i += len(value)-1
						}
						else {
							double, ok := strconv.parse_int(value)
							if !ok do panicl(path, line, column, "Expected an int but could not parse", value)
							value_type = nil
							// TODO: dont do this pointless back & forth |b| runes & string
							result.super_table[runes_to_key(key_buffer[:key_len], data_allocator)] = double
							clear(&value_buffer)
							key_len = 0
							i += len(value)-1
						}
					}
					else if unicode.is_alpha(c) {
						switch value {
						case "true", "false":
							val := true if value == "true" else false
							value_type = nil
							// TODO: dont do this pointless back & forth |b| runes & string
							result.super_table[runes_to_key(key_buffer[:key_len], data_allocator)] = val
							clear(&value_buffer)
							key_len = 0
							i += len(value)-1
						case "nan", "inf":
							unimplemented("nan and inf")
						}
					}
					// TODO: this (shouldn't) cause string parsing to break???
					// else {
					// 	panicl(path, line, column, "Invalid value presented:", value)
					// }
				}
			}
		}
	}

	log.info(result)

	return
}