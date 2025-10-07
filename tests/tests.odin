package tests

import "../toml"
import "core:testing"
import vmem "core:mem/virtual"

@test
empty :: proc(t: ^testing.T) {
	toml, err := toml.parse_from_filepath("./tests/empty.toml")
	testing.expect(t, err == .None)
}

@test
simple :: proc(t: ^testing.T) {
	arena: vmem.Arena
	allocator := vmem.arena_allocator(&arena)

	data, err := toml.parse_from_filepath("./tests/simple.toml", data_allocator = allocator)

	inline := make(map[toml.Toml_Key]toml.Toml_Value)
	defer delete(inline)
	inline["key"] = "yeah"
	
	testing.expect(t, err == .None)
	testing.expect(t, len(data.super_table["list"].(toml.Toml_Array)) == 9)
	testing.expect(t, data.super_table["bool"].(bool) == true)
	testing.expect(t, data.super_table["other"].(toml.Toml_Map)["hi"].(i64) == 1323)
	testing.expect(t, data.super_table["string"].(string) == "value")
	testing.expect(t, data.super_table["float"].(f64) - 82.233333333333337 < 0.01)
	testing.expect(t, data.super_table["inline"].(toml.Toml_Map)["key"].(string) == inline["key"].(string))
	testing.expect(t, data.super_table["escaped"].(string) == "va\nlue")
	testing.expect(t, data.super_table["raw"].(string) == "va\\nlue")

	vmem.arena_destroy(&arena)
}