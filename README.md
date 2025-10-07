# [TOML](https://toml.io/en/) parser written in [Odin](https://odin-lang.org).

The parser does not support unmarshalling or even writing TOML yet, just reading into a table.

The implementation is close to the spec, but not quite there, here is a list of weak points:
- Raw and multi-line strings aren't airtight, need work

To build and run the tests, just use `odin test tests/`. I'm assuming you have the Odin compiler and know what the language is, otherwise check out the [Overview](https://odin-lang.org/docs/overview/) for an idea, and the [site](https://odin-lang.org) for installation instructions. 

## Example:

simple.toml
```toml
key = "value"

[map]
inner = 1
boop = 'raw\w\w\e\ string\n'
```

main.odin
```go
import "path/to/the/package/toml"

import "core:fmt"

main :: proc() {
	data, err := toml.parse_from_filepath("./simple.toml", data_allocator = allocator)

	assert(data.super_table["key"].(string) == "value")
	assert(data.super_table["map"].(^toml.Toml_Map)["inner"].(i64) == 1)
	assert(data.super_table["map"].(^toml.Toml_Map)["boop"].(string) == "raw\\w\\w\\e\\ string\\n")

	fmt.printfln("%#v", data)
}
```

## Notes on code quality

The code is bad, and imagines that we are still for some reason living in the 1980s, where data structures wren't invented yet. The code could only be improved if Odin had gotos...

The best way anyone can contribute to this project would be to rewrite it from scratch.

## Missing features from the spec:

- [ ] List tables (\[\[table\]\] type of thing)
- [ ] nan, inf being parsed as 'keywords'