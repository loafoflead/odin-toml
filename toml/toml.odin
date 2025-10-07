/*
	TODO: documentation overview
*/
package toml

/*
	Toml v1.0.0, in Odin (of course). Link: https://toml.io/en/v1.0.0

	Author: loafoflead (keith.shale680@passinbox.com)
*/

import "base:runtime"

import "core:time"
import "core:time/datetime"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:slice"
import "core:unicode"
import "core:unicode/utf8"

import "core:log"
import "core:fmt"

Toml_Array :: [dynamic]Toml_Value
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
	time.Time,
	Toml_Array,
	Toml_Map,
}

Toml_Value_Type :: enum {
	String,
	Raw_String,
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

// A TOML file consisting of any metadata about the file, and a super table
// containing key-value pairs as well as lists and sub-tables.
Toml_File :: struct {
	super_table: Toml_Map,
}

runes_to_key :: proc(s: []rune, allocator: runtime.Allocator) -> Toml_Key {
	return Toml_Key(utf8.runes_to_string(s, allocator))
}

// Panics and displays the path, line, and column where it did
// the arguments don't pass properly but the correct information is conveyed
panicl :: proc(path: string, line, column: int, args: ..any) -> ! {
	loc := fmt.tprintf("%s(%i:%i):", path, line, column)
	log.panic(loc, args)
}

// @TODO: could prob lowkbert just use an arena that is part of Toml_File struct

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

	key_depth: int
	key_parents := make([dynamic]Toml_Key, allocator=data_allocator)

	key_buffer: [LARGEST_KEY]rune
	key_len: int
	MAX_ARRAY_DEPTH :: 32

	Array_Key :: union {
		Toml_Key, int
	}

	current_table_key: Toml_Key
	current_table := &result.super_table
	_current_table: Toml_Map

	array_depth: int
	array_keys: [dynamic]Array_Key = make([dynamic]Array_Key, len=MAX_ARRAY_DEPTH, cap=MAX_ARRAY_DEPTH, allocator = temp_allocator)
	arrays: [dynamic]Toml_Array = make([dynamic]Toml_Array, len=MAX_ARRAY_DEPTH, cap=MAX_ARRAY_DEPTH, allocator = temp_allocator)

	preinline_map: ^Toml_Map
	inline_maps_depth: int
	inline_map_keys := make([dynamic]Toml_Key, len=MAX_ARRAY_DEPTH, cap=MAX_ARRAY_DEPTH, allocator = temp_allocator)
	inline_maps: map[Toml_Key]^Toml_Map = make(map[Toml_Key]^Toml_Map, allocator = temp_allocator)

	value_type: Maybe(Toml_Value_Type)
	value_buffer: [dynamic]u8 = make([dynamic]u8, temp_allocator)

	// string
	escaping: bool
	multi_line: bool
	// end-string

	// numbers
	Signum :: int
	leading_sign: Maybe(Signum)
	//

	for i < len(content) {
		c := content[i]
		// log.infof("(%i, %i) %c, in_array: %v, in_map: %v, key: %v, value_type: %v, skipping: %v", line, column, c, array_depth > 0, inline_maps_depth > 0, key_buffer[:key_len], value_type, skip_line)

		// insane that this literally solves a problem i constantly have
		// defer in Odin is the best there is and the best thing in the omniverse (probably)
		defer {
			column += 1
			i += 1
			ir += 1
		}

		if skip_line && c != '\n' do continue
			// log.infof("%c, %i, (%i, %i)", c, i, line, column)

		if key_len == 0 && array_depth == 0 {
			switch c {
			case '#':
				skip_line = true
			case '}':
				if inline_maps_depth > 0 {
					if inline_maps_depth == 1 do current_table = preinline_map
					else {
						current_table = inline_maps[inline_map_keys[inline_maps_depth-1]]
					}

					inline_maps_depth -= 1
				}
				else {
					panicl(path, line, column, "did not expect table closing here")
				}
			case '\n':
				line += 1
				column = 1
				skip_line = false
			case '"':
				unimplemented("Declaration of a quoted key")
			case '[':
				end_ident := strings.index(content[i:], "]")
				value := content[i+1:i+end_ident]

				current_table_key = Toml_Key(value)

				if _, ok:=result.super_table[current_table_key]; !ok do result.super_table[current_table_key] = make(Toml_Map, data_allocator)
				k_ptr, v_ptr, _, _ := map_entry(&result.super_table, current_table_key)
				#partial switch &v in &result.super_table[current_table_key] {
				case Toml_Map:
					current_table = &v
				case:
					// compiler bug made me...
					unreachable()
				}

				i += len(value)+1
			case ' ', '\t', '\r', ',':
				continue
			case:
				idx: int
				// keys can have unicode in them, so we need runes
				for r, i in content[i:] {
					if unicode.is_white_space(r) || r == '=' do break

					if r == '.' {
						key_depth += 1
						key := runes_to_key(key_buffer[:key_len], data_allocator)
						append(&key_parents, key)
						key_len = 0
						idx = 0
						continue
					}

					if idx > len(key_buffer)-1 do panicl(path, line, column, "Key must (for now) be less than", len(key_buffer), "runes.")

					key_buffer[idx] = r
					key_len += 1
					idx += 1
				}
				// log.infof("%#v -> %s", key_parents, key_buffer[:key_len])
				// TODO: i bet this will be the source of an error, mark my words
				i += key_len		
			}
		}
		else { // key found
			if type, ok := value_type.?; ok {
				switch type {
				case .String, .Raw_String:
					if type != .Raw_String && c == '\\' {
						escaping = true
						continue
					}
					else if c == '"' || (type == .Raw_String && c == '\'') {
						end := true
						if multi_line {
							if !(len(content) > i + 3 && ((content[i+1] == '"' && content[i+2] == '"') || (type == .Raw_String && content[i+1] == '\'' && content[i+2] == '\''))) {
								end = false
							}
							else {
								i += 1 if escaping else 2
							}
						}
						if end && !escaping {
							multi_line = false
							value_type = nil
							value := make([]u8, len(value_buffer), data_allocator)
							copy_from_string(value, string(value_buffer[:]))
							// TODO: dont do this pointless back & forth |b| runes & string
							if array_depth > 0 {
								append(&arrays[array_depth-1], string(value))
							}
							else {
								/*if inline_maps_depth > 0 {
									inline_maps[inline_map_keys[inline_maps_depth-1]] = string(value)
								}
								else do */
								og := current_table
								if key_depth > 0 {
									for papi in key_parents {
										if _, ok:=current_table[papi]; !ok do current_table[papi] = make(Toml_Map, data_allocator)
										#partial switch &v in &current_table[papi] {
										case Toml_Map:
											current_table = &v
										case:
											// compiler bug made me...
											unreachable()
										}
									}
									key_depth = 0
									clear(&key_parents)
								}

								current_table[runes_to_key(key_buffer[:key_len], data_allocator)] = string(value)
								current_table = og
							}
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
							unimplemented(fmt.tprintf("Escape '\\%c'", c))
						}
						// TODO: are there any multi-line escapes?
						escaping = false
					}
					else {
						append(&value_buffer, c)
					}
				case .Int, .Float, .Bool:
					// these are parsed automatically upon detection
				case .Date_Time, .Time, .Array, .Map:
					unimplemented(fmt.tprintf("Parse value of type %v", type))
				}
			}
			else { // no type determined yet
				switch c {
				case '#':
					panicl(path, line, column, "Declarations must be of the form key = value, unexpected comment found")
				case '\n':
					if array_depth == 0 {
						panicl(path, line, column, "Declarations must be on the same line")
					}
				case '"':
					if len(content) > i + 3 && content[i+1] == '"' && content[i+2] == '"' {
						multi_line = true
						i += 2
					}
					value_type = .String
				case '\'':
					if len(content) > i + 3 && content[i+1] == '\'' && content[i+2] == '\'' {
						multi_line = true
						i += 2
					}
					value_type = .Raw_String
				case '+','-':
					leading_sign = +1 if c == '+' else -1
				case ']':
					// log.infof("%#v, %#v, %i", array_keys, arrays, array_depth)
					if array_depth > 0 {
						switch v in array_keys[array_depth-1] {
						case int:
							append(&arrays[v], arrays[array_depth-1])
						case Toml_Key:
							current_table[v] = arrays[array_depth-1]
						}
						array_depth -= 1
						arrays[array_depth] = nil
						// remove(&arrays, array_depth-1)
						key_len = 0
					}
					else do panicl(path, line, column, "Should not be closing array before opening it, my bad")
				case '[':
					value_type = nil
					array_depth += 1
					arrays[array_depth-1] = make(Toml_Array, data_allocator)
					if array_depth == 1 {
						array_keys[array_depth-1] = runes_to_key(key_buffer[:key_len], data_allocator)
					}
					else {
						array_keys[array_depth-1] = array_depth-2
					}
					// why am i coding this like its 1981
					key_len = 0
				case '{':
					value_type = nil
					inline_maps_depth += 1
					if inline_maps_depth == 1 {
						preinline_map = current_table
					}
					key := runes_to_key(key_buffer[:key_len], data_allocator)
					
					inline_map_keys[inline_maps_depth-1] = key

					// og := current_table
					if key_depth > 0 {
						for papi in key_parents {
							if _, ok:=current_table[papi]; !ok do current_table[papi] = make(Toml_Map, data_allocator)
							#partial switch &v in &current_table[papi] {
							case Toml_Map:
								current_table = &v
							case:
								// compiler bug made me...
								unreachable()
							}
						}
						key_depth = 0
						clear(&key_parents)
					}
					if _, ok:=current_table[key]; !ok do current_table[key] = make(Toml_Map, data_allocator)
					// current_table = og

					#partial switch &v in &current_table[key] {
					case Toml_Map:
						inline_maps[key] = &v
						current_table = &v
					case:
						// compiler bug made me...
						unreachable()
					}
					
					key_len = 0
				case ',':
					continue
				case ' ', '\t', '\r':
					continue
				case:
					// .......\n.......
					// newline^
					//		  v
					// [..][..][..][..]

					newline := strings.index_any(content[i:], "\n,]}")
					slice: string
					if newline == -1 do slice = content[i:]
					else do slice = content[i:i+newline]
					// log.infof("\n----\n%s\n----\n",content[i:])
					value := strings.trim(slice, " ")
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
							val: Toml_Value
							dt, utc_offset, is_leap, consumed := time.rfc3339_to_components(value)
							val = dt
							// log.info(value, dt)
							err := datetime.validate_datetime(dt)
							if err != nil {
								sb := strings.builder_make(allocator=temp_allocator)
								strings.write_string(&sb, "1970-01-01T")
								strings.write_string(&sb, value)
								s := strings.to_string(sb)
								nt, consumed := time.rfc3339_to_time_utc(s)
								val = nt
								// log.info(s, nt)
								// serr := datetime.validate_time(transmute(datetime.Time)nt)
								// if serr != nil {
								// 	strings.builder_reset(&sb)
								// 	strings.write_string(&sb, value)
								// 	strings.write_string(&sb, "T00:00:00")
								// 	s = strings.to_string(sb)
								// 	date, _, _, _ := time.rfc3339_to_components(s)
								// 	log.info(s, date)
								// 	gerr := datetime.validate_datetime(date)
								// 	panicl(path, line, column, fmt.tprintf("Invalid datetime format: %v", gerr))
								// }
							}
							if array_depth > 0 {
								append(&arrays[array_depth-1], val)
							}
							else {
								og := current_table
								if key_depth > 0 {
									for papi in key_parents {
										if _, ok:=current_table[papi]; !ok do current_table[papi] = make(Toml_Map, data_allocator)

										#partial switch &v in &current_table[papi] {
										case Toml_Map:
											current_table = &v
										case:
											// compiler bug made me...
											unreachable()
										}
									}
									key_depth = 0
									clear(&key_parents)
								}

								current_table[runes_to_key(key_buffer[:key_len], data_allocator)] = val
								current_table = og
							}
							clear(&value_buffer)
							key_len = 0
							i += len(value)-1
						}
						else if strings.contains(value, ".") {
							real_value, _ := strings.replace(value, "_", "", -1, allocator=temp_allocator)
							double, ok := strconv.parse_f64(real_value)
							if !ok do panicl(path, line, column, "Expected a float but could not parse", real_value)
							value_type = nil
							if sign, ok := leading_sign.?; ok do double *= f64(sign)
							leading_sign = nil
							if array_depth > 0 {
								append(&arrays[array_depth-1], double)
							}
							else {
								og := current_table
								if key_depth > 0 {
									for papi in key_parents {
										if _, ok:=current_table[papi]; !ok do current_table[papi] = make(Toml_Map, data_allocator)
										#partial switch &v in &current_table[papi] {
										case Toml_Map:
											current_table = &v
										case:
											// compiler bug made me...
											unreachable()
										}
									}
									key_depth = 0
									clear(&key_parents)
								}
								current_table[runes_to_key(key_buffer[:key_len], data_allocator)] = double
								current_table = og
							}
							clear(&value_buffer)
							key_len = 0
							i += len(value)-1
						}
						else {
							real_value, _ := strings.replace(value, "_", "", -1, allocator=temp_allocator)
							double, ok := strconv.parse_int(real_value)
							if !ok do panicl(path, line, column, "Expected an int but could not parse", real_value)
							value_type = nil
							if sign, ok := leading_sign.?; ok do double *= int(sign)
							leading_sign = nil
							if array_depth > 0 {
								append(&arrays[array_depth-1], double)
							}
							else {
								og := current_table
								if key_depth > 0 {
									for papi in key_parents {
										if _, ok:=current_table[papi]; !ok do current_table[papi] = make(Toml_Map, data_allocator)
										#partial switch &v in &current_table[papi] {
										case Toml_Map:
											current_table = &v
										case:
											// compiler bug made me...
											unreachable()
										}
									}
									key_depth = 0
									clear(&key_parents)
								}
								current_table[runes_to_key(key_buffer[:key_len], data_allocator)] = double
								current_table = og
							}
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
							if array_depth > 0 {
								append(&arrays[array_depth-1], val)
							}
							else {
								og := current_table
								if key_depth > 0 {
									for papi in key_parents {
										if _, ok:=current_table[papi]; !ok do current_table[papi] = make(Toml_Map, data_allocator)

										#partial switch &v in &current_table[papi] {
										case Toml_Map:
											current_table = &v
										case:
											// compiler bug made me...
											unreachable()
										}
									}
									key_depth = 0
									clear(&key_parents)
								}
								current_table[runes_to_key(key_buffer[:key_len], data_allocator)] = val
								current_table = og
							}
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

	// result.super_table[current_table_key] = current_table^

	log.infof("%#v", result)

	return
}