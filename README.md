# [TOML](https://toml.io/en/) parser written in [Odin](https://odin-lang.org).

The parser does not support unmarshalling or even writing TOML yet, just reading into a table.

The implementation is close to the spec, but not quite there, here is a list of weak points:
- Raw and multi-line strings aren't airtight, need work

To build and run the tests, just use `odin test tests/`. I'm assuming you have the Odin compiler and know what the language is, otherwise check out the [Overview](https://odin-lang.org/docs/overview/) for an idea, and the [site](https://odin-lang.org) for installation instructions. 

## For those interesting in actually good parsers:

- https://github.com/mkozhukh/odin-toml -- Probably the best one out there, spec compliant and supports marshalling and unmarshalling with a simple interface.
- https://codeberg.org/spindlebink/toml-odin -- Bindings to the [tomlc99](https://github.com/cktan/tomlc99) library in Odin, professional.
- https://github.com/Up05/toml_parser -- An almost immediate-mode style parser with an intuitive and Odin-like style of parsing that takes advantage of or_else and similar to make walking the file simple and quite readable. Also the project with some of the best documentation readily available on its repository.
- https://gitlab.com/froge/toml-odin -- Not totally spec compliant but quite clean code that looks like it would be nice for hacking at, a stepping parser too allowing the user to do their own step parsing (like the visitor pattern).

If you know of any others that you think should be on this list of better parsers on this parser's github page that shan't be seen by anybody, feel free to make an issue (/hj). The above is just a list of things I found searching on the discord.

Note: https://pkg-odin.org/ is a repository of Odin packages if you would like to search it.

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

## TODOs:

- [X] Make inline maps less janky
- [ ] Unmarshalling and Marshalling
- [ ] Break up parsing into steps, notably to allow you to jump key-value pair by key-value pair
- [ ] If possible when parsing into steps, make it so you can 'stream' in the input to control allocations
- [ ] Finish supporting the spec