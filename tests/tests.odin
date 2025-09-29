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

	toml, err := toml.parse_from_filepath("./tests/simple.toml", data_allocator = allocator)
	testing.expect(t, err == .None)

	vmem.arena_destroy(&arena)
}