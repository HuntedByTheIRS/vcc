# Changelog

What has landed in this tree, oldest first, the way a GNU changelog appends.

One entry per commit, under the date it landed: the area the commit names
itself with, what it changed, and the commit in brackets. The commit is where
the author and the reasoning are, so this file does not repeat them. Merge
commits and the badge commits the workflows write are left out, since neither
changes anything a reader of this file came for.

An entry is added by hand for the work, not generated: `docs:` for prose,
`tree:` for something that touches everything, and the module's own name when
it owns the change, which is the same vocabulary the commits use.


## 2026-09-28

* Initial commit (504c9e6)
* tree: the module and editor scaffolding joins the history (67e93c2)
* v.mod: the license name matches the LICENSE file (fff6783)
* docs: a README that states the two constraints and the real status (eed308a)
* docs: a contributor guide with the speed rule spelled out (279b568)
* docs: an agent guide with the tree's hard rules in it (bfd6c8f)
* ignore: agent state stays out of the tree (9909833)
* docs: the Contributor Covenant, verbatim (b88bce3)
* docs: what a useful compiler bug report looks like (f8bc75c)
* docs: discussions, and the categories that actually exist (a4016e0)
* docs: security, for a program whose job is to emit executables (45a5148)
* docs: the road from the stub to a swap, with the speed gate on every leg
  (a438a7b)
* github: the bug form asks a compiler's questions (71fc01c)
* github: the feature form routes by compiler stage (dcdc42a)
* github: the issue chooser points at the channels that are real (1ce0fe2)
* github: three discussion forms, one per category that wants structure
  (1fdddb7)
* docs: discussions names the forms (218eb6c)
* docs: the agent guide names the tool directories too (5ef5b4a)
* tokenize: a lexer for C's preprocessing tokens (19ec9aa)
* ast: the shapes the stub compiles, and the locations they came from
  (52a8151)
* parser: recursive descent for the subset, with recovery (186d4c5)
* backend: a target described as tables instead of branches (751d117)
* codegen: fold a constant body into an ELF64 image that runs (f0e6de5)
* cli: the command line a C compiler in this position is handed (bacebae)
* main: the pipeline, wired end to end (dbd0e26)
* codegen: fold a long operator chain with a loop, not with recursion
  (d1f71ec)
* parser: a bad statement costs one diagnostic, and nesting is bounded
  (5530d5c)
* tools: a gate for the rules and a harness for the numbers (3bfc8c4)
* docs: the layout that exists, the chain that is the goal, the real numbers
  (e07b6cc)
* printer: turn a tree into text (9977e18)
* optimizer: levels, a pass table and a builtin table (a18f648)
* cli: the flags for a level, for builtins, and for reading the tree (e8e4e97)
* docs: the optimizer, the dump flag, and the plan for beating tcc (885e700)
* github: the gate runs in CI, and a release checks what it publishes
  (09808ac)
* tools: the gate reads the CI configuration (ef6af97)
* docs: the V this tree needs, and how a release happens (6912463)
* backend: split a target into a machine and a system (6203fc6)
* cli: -std takes its value either way it is written (fc9b15f)
* docs: how to write here, in both files (87d2305)
* github: the release smoke test under bash -e (fb26b48)

## 2026-09-29

* ast: the nodes a string literal and an expression statement need (512afd6)
* tokenize: a token and a diagnostic name their file (e7b34f0)
* tokenize: a hash opens a directive only at the start of a line (287b060)
* preprocess: read the directives and expand object-like macros (6277ebc)
* preprocess: the conditionals, and the arithmetic an #if needs (8eb5242)
* preprocess: #include, with C's search order and a stack of files (4581d21)
* backend: the instruction encoders and loader facts an emitter needs
  (276e132)
* codegen: emit dynamically linked images that call libc (5d17220)
* preprocess: expand macros that take arguments (056b34f)
* tokenize: a comment in a directive line, and one that runs past it (6776dae)
* preprocess: expand a run of text, and define the macros that describe the
  target (51a10f4)
* parser: an expression statement and a string literal (614dafb)
* parser: read the declarations a preprocessed header is made of (75e369b)
* tokenize: spell the directive line the way the gate allows (329cefb)
* preprocess: #include_next reads the copy after the one being read (ba5398a)
* main: -run gives the program the terminal instead of a pipe (ad20c15)
* preprocess: #line, the clock macros, __COUNTER__ and _Pragma (13b11e4)
* ast: the nodes a function body with variables and branches needs (9075641)
* diagnostics: a warning is not an error, and -w is real (8f751fa)
* backend: the instructions a frame with locals, branches and arithmetic
  needs (9771390)
* preprocess: the flags a build tool asks a compiler for (5139567)
* parser: the statements of a body are read in one place (2eb2462)
* preprocess: the macros that ask a compiler about itself (fc5a0f9)
* parser: a declaration inside a body is a variable (6983d22)
* parser: an assignment writes to a name (024a110)
* parser: the operators a condition is written with (bd936c7)
* parser: if chooses, while goes round, and break leaves (b077aa4)
* preprocess: a macro that takes arguments is one that was given a list
  (81d7296)
* parser: a for is a block and a while (f77b716)
* documents: say what the tree does now, and measure the speed claim again
  (ae34209)
* codegen: a frame with locals, parameters and computed expressions (478b070)
* main: -MD writes the rule and goes on to compile (775de7e)
* codegen: if, while, break and continue as branches and jumps (00e2f42)
* codegen: pin the shape a for is desugared into (747909b)
* codegen: a continue runs the step of a for (e9329c8)
* documents: the function bodies run, and the call's value is the open edge
  (874ecf3)
* optimizer: a declaration keeps its parameters through the rewrite (987f2cb)
* codegen: a call's value can be read (4b9eef3)
* codegen: a char is a byte in the frame and an int when it is read (0b24764)
* ast: the nodes an array element needs (d7ee4d0)
* parser: an array declaration keeps its size, and an element has a subscript
  (ae1e19a)
* backend: the address of an element, and the moves through an address
  (ed86dfd)
* codegen: an array is a block of the frame, and an element is an address
  (f66c763)
* ast+parser: a top-level object definition is storage the tree carries
  (43fbca3)
* codegen: the image holds the objects defined at the top level (c8090fd)
* codegen: the address of a local, and a definition that returns void
  (37ad20b)
* diagnostics: the class, the severity policy and the renderer (d1ceb68)
* standard: the dialect table and the feature table (938e25c)
* extensions: the registry and the -fvcc-exts= flags (71ce952)
* cli: the -std= dialect, the warning flags and the extension flags (250d546)
* preprocess: the macros that name the language (09dee39)
* main: the mode, the dialect check and the rendered diagnostics (4cde83d)
* standard: the __asm__ row names every shape the spelling marks (c76dc93)
* standard: the __attribute__ row is true of every position the spelling has
  (36a427a)
* standard: the _Static_assert row records where the compiler meets it
  (83e00d7)
* diagnostics: a read-only run reports without promotion (870af3b)
* main: -M and -E are not stopped by a promoted pedantic message (d4e98c4)
* docs: -std=c99 defines __STRICT_ANSI__ and takes the strict headers
  (3ae5dc1)
* main: a read-only run reports the preprocessor stage without promotion
  (d3d92c6)
* types: the type model of the C99 types (af33dd2)
* types: the words of a declaration add up to a type (beac6c7)
* tokenize: the translation phases run before the lexer reads a byte (3063dce)
* types: the object representation, asked of the target description (cc90aee)
* tokenize: identifiers hold universal character names and the dollar
  (8467570)
* tokenize: a test for each literal class C99 adds (9f3f6ab)
* types: the conversions of clause 6.3 (bd226d3)
* parser: the refusal of a hexadecimal float names the construct (97466d6)
* types: the symbol table, the scopes and linkage (378f0b9)
* preprocess: adjacent string literals are one literal (6cc8653)
* types: the type of an integer constant, and the pieces the typed tree asks
  for (8b48bfe)
* ast, parser: every node carries the type it resolved to (898998a)
* printer: -print-ast renders the type each node resolved to (5d55ff7)
* standard: the dialect rows for the C99 types the model resolves (a7d80f7)
* parser: the refusal names the type where the answer is about the type
  (2ef3048)
* types: the width of a byte is one fact, and it is written once (c2bf1b0)
* preprocess: narrow the written record about mixed-prefix concatenation
  (fd22a38)
* tokenize: gate trigraph replacement on the selected dialect (54862ab)
* types: the enum promotion is recorded as a divergence from gcc (5a8440e)
* standard: the row comment says which path names a type in full (e86db6f)
* types: the null pointer constant wins over the pointer to function, and
  _Bool takes a pointer (029d672)
* types: the three character types are three types, not one (e643cdf)
* types: the pointer rules of 6.5.16.1 live in one function (4e9fb56)
* parser, codegen, standard: a node the model did not type is refused, not
  written (8f91782)
* parser: a file-scope initializer the literal reader refuses is named at the
  literal (5026f5d)
* types: the description carries the width of an int and of an unsigned int
  (fbe05af)
* parser: the record and the tests follow the widths the description now
  carries (447bb64)
* parser: a name nothing in the unit declares is refused, not written
  (f04c223)
* parser: the assignment constraint is asked wherever an assignment is
  written (b3f7124)
* parser: a name a refused declaration declares is recorded as declared
  (34c1c1c)
* parser: the null pointer constant is the value of the expression, not a
  literal (0c56e8b)
* parser: a call to a name that is not a function is refused, not written
  (90f7e7f)
* codegen: the boundary comment names the call case it claimed was closed
  (bf5e80c)
* parser: a redeclaration with a different type in one scope is refused
  (db905a5)
* parser: a keyword cannot be the name of a declaration (8065d08)
* backend: a target says where the system keeps its libraries (abd83e6)
* codegen: a -l name is read into the library it stands for (662a568)
* codegen: the image names the library a -l flag asked for (cc3083c)
* backend: the machine has a floating-point register file (31f0b6d)
* parser: a floating constant is read as the double it is (7021d1c)
* parser: a file-scope initializer may be a floating constant (6924584)
* codegen: a double is a value in the floating-point register file (7c70480)
* codegen: an error that reached no diagnostic is reported (b051cb7)
* types: a double has a width on this target (d66ff9a)
* codegen: a local in the library reader is renamed off a function name
  (709dd7d)
* parser: a name this file declared as a type is the type it names (a94360e)
* pipeline: a typedef is the type it names, end to end (907d7ae)
* docs: the README's status is what the tree does now (69b3f3d)
* docs: the roadmap's "where the tree is" says where it is (1294764)
* docs: the agent guide writes its clipped negation as a clause (6583c64)
* docs: the roadmap says it without em dashes (25fcfc5)
* docs: the readme says it without em dashes (eb9f4a5)
* docs: the security page names its categories in sentences (66472f8)
* docs: the issue page names its three shapes in sentences (87e06c3)
* types: the description carries a char's width (9a40d11)
* parser,codegen: an object of a struct type, and a member of it (45e5306)
* backend: the machine can push an argument and give the stack back (2760be7)
* codegen: the arguments past the registers are passed on the stack (52737db)
* docs: the readme says what the tree does with structs and with long calls
  (217f382)
* docs: the roadmap lists the walls that are down (aab8d15)
* ast, backend: a member can be read through a pointer (481c3d2)
* parser, codegen: a member is read from the object a path names (36bcf8b)
* docs: the readme's list loses the two member shapes that landed (786eac3)
* docs: the roadmap's list of what is left says what is left (8ba18ac)
* parser, codegen: a top-level aggregate is storage in the image (2edab34)
* docs: the readme says where an aggregate lives (abd7a0b)
* docs: the roadmap's list says an aggregate by value is what is left
  (a4b610d)
* ast, backend: an element of an array whose stride the scaled address cannot
  write (92a4173)
* parser, codegen: an array of aggregates is a stride and a count (b28b9c2)
* docs: the readme's list loses the array of aggregates that landed (2c04834)
* docs: the roadmap's list of what is left loses an array of aggregates
  (00ba1f6)
* ast, parser, types: an object of an aggregate type of one eightbyte
  (d72cd8d)
* codegen: an object of an aggregate type is handed over in a register
  (cd43c5c)
* codegen: an object is handed back from a function and copied into an object
  (5490be8)
* docs: the readme says how an object of an aggregate type is handed over
  (e6e4867)
* docs: the roadmap keeps the eightbyte limit as what is left (e157d64)
* ast, parser: the class of every eightbyte an object is split into (29ba0ea)
* codegen: an object of two eightbytes is handed over in a pair of registers
  (3293e63)
* codegen: an object of two eightbytes is handed back in a pair of registers
  (f35b4b3)
* docs: the readme says an object of one or two eightbytes travels in
  registers (428c8cb)
* docs: the roadmap keeps the two-eightbyte limit as what is left (b82242f)
* codegen: an object of more than two eightbytes is passed in memory (e5df280)
* codegen: an object of more than two eightbytes is handed back through an
  address (25d158c)
* docs: the readme says how an object of any size is handed over (ce275bc)
* docs: the roadmap's list of what is left loses the object by value (0f00867)
* docs: the readme writes its clipped negation as a clause (becc93e)
* parser: a diagnostic names the file its token came from (300325a)
* parser: sizeof reads a type name or an expression and answers its size
  (3458907)
* codegen: a cast converts between the classes the back end carries (949870f)
* codegen: two addresses are compared at the width of a word (cf0cc18)
* codegen: * reads the value at an address (936ef5f)
* parser: a static function nothing names is stepped over (c22063f)
* docs: the readme and roadmap say what compiles now (6f91fa8)
* codegen: the library script test names a library the machine has (8fd41ca)
* github: the newer-V job names the binary it just built (b5dd72a)
* parser: typeof is read as a type specifier (5ef841a)
* standard: the typeof row is implemented (559f509)
* docs: the readme and roadmap name typeof (0c6aa2a)
* types: the 128-bit integer types are in the model (6d225ad)
* parser: __int128 is read as a type word (5ae6cfc)
* standard: the 128-bit row reports in a strict mode (a12c91d)
* docs: the readme and roadmap name the 128-bit type (ddaafee)
* backend: an arithmetic shift right is an instruction the arch has (4a29f3c)
* codegen: a 128-bit object is sixteen bytes of storage (278dc8a)
* codegen: a 128-bit object is read by its low word (c4a231e)
* codegen: a 128-bit member is written at its own address (965686a)
* codegen: an element the machine cannot scale is a multiply, and sixteen
  bytes is a refusal (d4ad9aa)
* codegen: a narrower slot takes the low word of a 128-bit object (6ff7467)
* codegen: an element of a 128-bit array is written at the element's address
  (7026ce7)
* codegen: a top-level object of 128 bits is reachable at its address
  (cba1c02)
* backend: the instructions a value two words wide needs (278a970)
* parser: the 128-bit type is read in a parameter list and as a return type
  (4187a82)
* types: the conversions with a 128-bit operand, measured (0912fa2)
* standard: typeof is four rows, because four spellings answer differently
  (b01ca15)
* standard: a mode without the construct refuses it, and no flag takes that
  back (e5896a3)
* codegen: a 128-bit value is a pair, and the two-word forms compute it
  (ef3ad61)
* codegen: two 128-bit values are multiplied, and the cross products are the
  whole of it (ca4b9ad)
* codegen: a pair is divided by a pair, and the routine is the compiler's own
  (dfd2a4a)
* parser: a shift and the three bitwise operators are read at C's levels
  (9c5c46b)
* codegen: the order of two pairs reads the right flag, and a cast to the
  type widens (eaed439)
* codegen: a shift and a bitwise operator, on a narrow value and on a pair
  (79b05ef)
* backend: the shifts whose count is in a register (49d4569)
* codegen: a shift by a count the program works out (eec9cb2)
* parser: every compound spelling is read, and the node it builds carries a
  type (4ddb19b)
* codegen: a function that returns a 128-bit value (548a77a)
* codegen: a 128-bit parameter and the call that passes it (33af68a)
* codegen: tests for a 128-bit return and a 128-bit parameter (155724a)
* codegen: a slot belongs to the frame it was cut from (23244b3)
* codegen: a top-level object of 128 bits keeps the sign of its initializer
  (7d71b73)
* parser: a file-scope initializer that is an expression is reported (498ee4d)
* codegen: a pointer to the type is a pointer (49b363f)
* codegen: the block a pair division works in belongs to the frame too
  (1869a4d)
* parser: the C23 _BitInt type is read at its own spelling (ac3df50)
* standard: the _BitInt row says which mode has the type (c49ea78)

## 2026-09-30

* codegen: a constant wider than the immediate is refused, not halved
  (fa13267)
* backend: the target tests compile, and a cache was hiding that they did not
  (1cb2673)
* backend: a machine and a system are each a module (9f8a336)
* image: the emitted unit gets a module of its own (e95f1e0)
* backend: the ELF container leaves codegen/ (d31fa4f)
* standard: the feature rows name the extension that brings each construct
  down (a0f6e66)
* extensions: the names come from the standard table, and honored is deleted
  (fbb66a6)
* cli: the extension help and comments report the derived names (9d862a2)
* codegen: the container tests name the container's constants by module
  (df16510)
* docs: the layout table names image and the ELF container (8587431)
* docs: the extension names come off the standard rows (fc53ff4)
* docs: the layout table names the emitted unit (336b1b1)
* backend: the machine's relocation numbers reach the target (fe0ff83)
* backend: the relocatable container, for -c (e290f50)
* codegen: -c emits an object rather than a program (5a304dd)
* backend: the library reader moves to the system whose libraries it reads
  (4cf97cc)
* docs: the commit areas name image (5277242)

## 2026-10-01

* docs: the commit areas name image in both files (5b19bca)
* backend: a target name becomes a target in one place (53af1af)
* parser: the front end parses for the target it was handed (bac0192)
* backend: the calling convention gets the module it will live in (9dac89f)
* codegen: the emitter asks the target how a value is handed over (983735b)
* parser: the class comes off the node, because a target answers it (9b98d5f)
* codegen: where a pair of eightbytes goes is the convention's answer
  (c1c8c30)
* backend: a register crosses the seam as a handle (7c6de58)
* preprocess: a character constant may name its encoding in an #if (1593790)
* preprocess: a diagnostic about an #if names where the construct is (8b3013e)
* preprocess: a GNU dialect claims a GNU compiler (7fe542d)
* parser: do { } while is a loop of its own (bd6c985)
* tokenize: a mode with the digraph spellings reads them (e7d6ae5)
* ast: a node for the increment and decrement operators (200f406)
* parser: read ++ and -- on a name (9c43a59)
* codegen: emit ++ and -- on a local or a top-level name (e9e58ca)
* parser: the step's refusal names the types it takes (1118a32)
* parser: a brace initializer is a list of constants (246cd6d)
* parser: a file-scope initializer in parentheses is the number in them
  (5dd0113)
* preprocess: the version comment does not explain its own numbers (7414c45)
* parser: an integer constant up to 2^64-1 is read and typed (168bb0d)
* types: the four 64-bit integer kinds carry the width this target gives them
  (7c0fc2f)
* parser: a 64-bit integer spelling names a type the emitter has (265a8dc)
* backend: the machine's eight-byte integer instructions (5c8e567)
* codegen: a value of an eight-byte integer type is computed at its width
  (8e08ab5)
* codegen: read the callee's parameter widths once per call (c8e411b)
* parser: sizeof answers a constant of the type the target gives size_t
  (d6b2100)
* types: carry the width of a float in the target description (b64e1c6)
* backend: encode the single-precision instructions (5b11a1b)
* parser: read the f and F suffixes on a floating constant (cc4f04c)
* parser: the conditional operator ?: is read, typed and emitted (d32cae8)
* parser: a chain of prefix operators is counted, not followed until the
  stack runs out (7e48606)
* parser: an assignment through a dereference stores through the pointer
  (f86fa85)
* types: a tag is the identity of a struct or union (e4cf09c)
* types: an aggregate with no members is not a size of zero (c87aa88)
* parser: goto, labelled statements and switch are read and emitted (dbbf9b0)
* codegen: test a store through an address byte by byte (39994d0)
* backend: negate a float at bit 31, its own sign bit (913befb)
* image: name a four-byte floating constant in the fixups (08eb010)
* parser: accept float as a type the back end has a form for (86c3765)
* codegen: emit a float as four bytes everywhere storage is (0250d26)
* codegen: a division by zero is refused where a constant is required, and
  nowhere else (238a948)
* codegen: carry a top-level object's float width out of its shape (c608d5f)
* codegen: write a top-level float initializer as four bytes (66b382a)
* codegen: test a floating value asked directly as a question (a923876)
* parser: a cast lookahead reads a type name, not a declaration (393811b)
* codegen: a double converts to an unsigned integer at the width it needs
  (6b28d48)
* parser: a void expression is read as a value to discard, not a refusal
  (55dd26c)
* codegen: an unsigned integer converts to a double zero-extended (409d3a0)
* parser: a subscript's base is an expression, not a name (d557bcf)
* parser: a parenthesised declarator keeps the order of its steps (9a1b57d)
* parser: a parameter list leaves the storage class of its declaration alone
  (0984961)
* parser: tests for the pairs the parenthesised declarator must keep apart
  (76fede4)
* parser: a subscript index and a call argument list are counted (b110571)
* types: the target description carries the character types and short
  (f47248a)
* parser: a sizeof operand is counted against the nesting limit (7c05d46)
* parser: tests for the three expression chains that ran the stack out
  (7751990)
* types: the object description carries the two-byte integers (c8297e4)
* backend: the machine moves a two-byte value (7553c3c)
* ast: a call carries the expression it calls (78655f6)
* codegen: a value of the character types, short and _Bool (87a574d)
* codegen: a constant stored into a member is written at the member's width
  (17b1c96)
* backend: an indirect call is the bytes that call a register (0242d42)
* parser: a call is read after any postfix expression (77763d9)
* parser: fold a cast in an integer constant expression (d4fa4d6)
* codegen: a function designator used as a value is its address (f94f8c7)
* ast: a function declaration says whether the file gave it a body (c0e1fb3)
* parser: evaluate a written array bound as an integer constant expression
  (e322a8e)
* codegen: a definition with an empty body is emitted and its calls are local
  (69a13a0)
* tree: a call to a same-unit definition is run for the void and int callees
  (d10a728)
* parser: refuse a non-constant array bound at file scope (3c38262)
* parser: the narrow integer spellings name types the emitter has (484386f)
* codegen: a read of an unsigned narrow type takes zero above it (19f47c1)
* types: the character types and _Bool, and not the two-byte integers
  (4104768)
* codegen: a constant stored into a member is written at the member's width
  (4b7550c)
* parser: a type-generic dispatch reads its two builtins (ae32414)
* parser: __builtin_offsetof reads the layout offset of a member (aaeedca)
* parser: __builtin_va_arg is refused by name (e664686)
* parser: a union's brace initializer stores into its first member (5bc2a08)
* parser, codegen: a union at the top level is initialized into the image
  (4cc7273)
* backend: the variadic save area and the argument list (731fdff)
* parser: __builtin_va_list is the argument list of the target (ec91c37)
* parser: the four argument-list operations are read, not refused (3c60ec3)
* parser: fold the conditional operator in an integer constant expression
  (94c6459)
* parser: fold the operators 6.6 leaves in an integer constant expression
  (a7dfa5c)
* parser: fold a floating constant as the immediate operand of a cast
  (af48b38)
* image: give a wide string literal its own place in the read-only data
  (60ce162)
* parser: read a wide string literal, and emit its address (1826bae)
* codegen: a value of a narrow type is converted on the way out and narrowed
  on the way in (fd81f2b)
* parser: initialize a file-scope object from an integer constant expression
  (33893a4)
* codegen: the width of an operator chain is walked without recursing per
  term (f4c2018)
* codegen: a chain of operators past the walk's bound is refused by name
  (83065cd)
* codegen: a call answers for its own type before its name is looked up
  (5864a71)
* parser: report a bound that names an undeclared name as that name (b547559)
* parser: an array suffix says whether it wrote a size (da5d76e)
* types: a declared name's type can be completed after its declarator
  (c3a24f3)
* codegen: a variadic definition saves its argument registers (a0ff22a)
* parser: a variadic definition is read, not refused (c5f1a69)
* tests: a variadic definition runs and answers what gcc answers (9e30f68)
* codegen: pass a float argument as a float to a declared callee (45c8ead)
* backend: an eight-byte integer converts to a double at its own width
  (04c5031)
* parser: a file-scope array takes a string literal initializer (1d32e03)
* parser: an array in a body takes a string literal initializer (43cea5d)
* codegen: the wide division propagates the load it was dropping (e008616)
* codegen: only an object declared as an argument list is walked (95f06ec)
* backend: a double converts to an eight-byte integer at its own width
  (3f4af78)
* codegen: a designator naming a declared function is its address (d2f63b3)
* parser: a character constant is a written constant in a brace initializer
  (242a439)
* parser, ast, codegen: a struct's brace initializer writes the values into
  its members (1393e48)
* parser: a pointer to a tag with no body is a complete object (a783853)
* parser: a parameter that is a pointer to a tag with no body is named too
  (96499e7)
* parser: a written bound is used as it was written (42aa20b)
* codegen: a call through a function pointer uses the type the pointer
  carries (5051e3b)

## 2026-10-02

* parser: pin the refusal of an assignment expression inside parentheses
  (f205fee)
* parser: read an assignment and a comma expression inside parentheses
  (cdd8643)
* parser: test the value an assignment and a comma expression carry (63a8051)
* codegen: an element store writes a constant at the element's width (cddc3d8)
* codegen: test an element store converts a constant to the element's width
  (08f323c)
* ast: carry a bitfield member's own bits (1170365)
* parser: record where a bitfield member's bits are (da1851d)
* backend: mask a register with a constant (3ebdca1)
* codegen: read a bitfield member from its own bits (de2db9d)
* codegen: write only a bitfield member's own bits (6d042db)
* codegen: refuse the address of a bitfield by name (22a6e4b)
* codegen: test bitfield reads and stores (8ca2f58)
* image: carry a reference inside the writable data (1bc22a7)
* backend: resolve a reference inside the writable data (a25bd7d)
* parser: a pointer object at the top level is storage (ce9cd9e)
* parser: walk an operator chain's left spine with a loop, not recursion
  (9522f38)
* parser: a top-level pointer holds an address, and the image writes it
  (070d1cb)
* parser, codegen: read and emit a GNU statement expression (10372e4)
* parser: read __func__, __FUNCTION__ and __PRETTY_FUNCTION__ (a566caf)
* parser, codegen: test statement expressions and the function-name spellings
  (203c286)
* parser: a top-level object whose initializer is an address (5f930b8)
* codegen: format the test file (3aafc4c)
* codegen: test a pointer against null at the width of an address (4156b5a)
* codegen: let a pointer be an operand of && and || (75becdd)
* backend: load the kernel's argument vector into the argument registers
  (0c5f0ce)
* codegen: hand the entry function the argument vector the kernel left
  (3af2450)
* preprocess: predefine the standard's floating-point and limit macros
  (f699c58)
* codegen: let ! take a pointer operand (a963eae)
* parser: read the __builtin_* values and classifications glibc's math.h
  calls (17f282a)
* codegen: keep the high word when an eight-byte value becomes a pointer
  (b25ba5e)
* codegen: take zeros above an unsigned four-byte value that becomes a
  pointer (b9deac9)
* parser: read an enumeration's names and give them their values (127caec)
* preprocess: check the predefines the standard names carry gcc's values
  (857515e)
* parser: read a declaration in a body that writes a tag and no object
  (5711779)
* parser: settle the brace-list tests on the refusals the reader gives
  (cadca68)
* codegen: run the two address-refusal tests through the refusing read
  (c95f837)
* parser: accept a definition whose return type is a pointer (ef8a5e4)
* codegen: emit a function whose return type is a pointer (e1f1d11)
* codegen: a dereference of a pointer to an array is the element address
  (2bf7288)
* ast: a member can carry the expression it is read from (a058493)
* codegen: address a member of an object that is an expression (6c09039)
* parser: read a member access after any postfix expression (7740887)
* parser: read a nested or designated brace list and initialize the object it
  names (307d68e)
* parser: read a constant expression as an element of a list in a body
  (cd8b422)
* parser: read universal character names in a string literal (d8550d4)
* codegen: address a row of a two-dimensional object by the row (05d3729)
* parser: read universal character names in a wide string literal (42d6364)
* parser: read universal character names in a character constant (f57c276)
* parser: adjust an array parameter to a pointer (83a141d)
* parser: refuse an array parameter whose element is void or incomplete
  (251da40)
* parser: a two-dimensional object in a body is a row per size (a18967a)
* parser: a parameter written with brackets is a pointer (9bfa55d)
* parser: say in the parameter comment that the bound does not travel
  (9c54db4)
* parser: read a comma in a for's init and update (d1add53)
* parser: read a comma expression in a for's condition (4521c8a)
* parser: read hexadecimal floating constants (4ed37ce)
* parser: read a compound literal in a body as an unnamed object (5c7aee6)
* parser: a sizeof of a compound literal is the size of its type (5dcaa04)
* parser: a compound literal at file scope has static duration (9e229b5)
* parser: refuse a compound literal the statement cannot build in place
  (b498567)
* parser: step a name of any integer width, not just an int or a char
  (480e9d1)
* parser: __real__ and __imag__ name the parts of a value (bb6bb0a)
* codegen: a pointer name steps by the size of what it points at (f0cf307)
* parser: a conditional's null pointer constant may be a void pointer cast
  (7f20685)
* types: give the complex types their representation, conversions and class
  (a2aa593)
* parser: a test for the class of every kind the class question reaches
  (4aa1fda)
* parser: read the complex types and the imaginary constants (0af02ea)
* abi: size a complex object by its two components (f3b2d1d)
* parser: size a complex declaration by the object it names (ba7558d)
* codegen: emit complex values, their arithmetic and the calls that take them
  (5b61cb6)
* codegen: step an element, a member or a dereference in place (71647d5)
* codegen: write a complex member and element by their own address (361d394)
* codegen: step a floating object by one of its own width (61b5036)
* codegen: take a register object argument's address before loading the
  registers (649367a)
* codegen: build a returned complex object once and read both its eightbytes
  (434344f)
* codegen: keep the complex product's formula and refuse the quotient
  (3298c6a)
* parser: an object of an enum type is read as the type gcc gives it (ab6546f)
* codegen: a value of an enum type is sized and signed by its underlying type
  (a5642f2)
* codegen: a function returns an unsigned int (9b78c21)
* parser: long double exists with literals, storage and the double
  conversions (0cc8338)
* parser: the class test names the enum kind the constructor now takes
  (c2f441a)
* backend/os: read the symbols a shared library defines (71f5f62)
* codegen: refuse an import no library the image names defines (1953fcc)
* tests: an unresolved external is refused at compile time (6b15810)
* codegen: refuse a long double returned from a function of another type
  (a7dde6c)
* codegen: convert a cast to the extended type before parking the destination
  (5e9bcdc)
* codegen: read an element of a top-level array of long doubles (86ff62e)
* parser: refuse a brace initializer for an array of long doubles (b71fa78)
* tree: update the long double test expectations and cover the paths (f4e66cf)
* parser: an enum type in the builtins test names its underlying kind
  (4a2fdd5)
* parser: read __real__ and __imag__ of a complex value as its part (ee2094a)
* codegen: read the part of a complex value into a register (697eb68)
* backend/os: ask a library's hash whether it defines a symbol (cfbf9fe)
* codegen: refuse a long double used as a subscript (52ba49b)
* parser: subtracting one pointer from another is a ptrdiff_t (02d8a40)
* codegen: the difference of two addresses counts elements (462c884)
* codegen: pin reading a component of a complex call result (561b7c5)
* parser: read chained assignment as the expression it is (7c51c7c)
* parser, codegen: pin chained assignment as an expression (647dcfb)
* parser: read an assignment in an initializer and a return value too
  (972fac1)
* codegen: keep a resolved callee where no argument can land on it (df01128)
* codegen: take an address at the level it is emitted at (2759a7e)
* backend: encode a frame subtraction by a register (28c9514)
* types: give a type a place to say its array bound is computed at run time
  (13bba64)
* ast: carry a run-time array bound and its size in the tree (2d48374)
* preprocess: open an absolute include path instead of searching for it
  (782616b)
* types: reference a run-time bound by a handle the reader keeps (33630a1)
* cli: refuse an object or an archive by name, not as source (1990999)
* codegen: claim and address a variable-length array's storage (5cd0484)
* cli: classify an input from the bytes the driver read (ad83515)
* preprocess: predefine the macros that identify this compiler (36900c1)
* cli: read the -print- flags and -verbose (563cd45)
* backend: answer a library file from the linker's own search (37ac432)
* cli, preprocess: emulate another compiler's identity with -femulation
  (9bc4c4b)
* parser: read _Static_assert as a declaration in both positions (eafa6b5)
* cli: answer the -print- flags and stop (7a630a2)
* preprocess: a token is hidden from the macros it came from, not from a
  stack (d3da6d1)
* cli: add -verbose (72e9487)
* parser: read _Generic and select on the controlling type (d4648c7)
* parser: read a bound that is a value as a variable-length array (16e9e74)
* parser: read C23's auto type specifier and take its type from the
  initializer (882b5e2)
* parser: a typedef names a struct that is completed later (ff74132)
* parser: read a GNU attribute after a tag body (9404465)
* standard: read the braced-group row, whose spelling is a pair of tokens
  (aee8e4b)
* standard: the sizeof row records the reader that landed (23a355b)
* tree: a built test executable is not content (f893ab6)
* tree: the test executables the suite writes are never content (2ee60e6)
* codegen: give a variable-length array's storage back at the end of its
  block (c4bbbbb)
* test: pin the block-scope release of a variable-length array (c6ddef4)
* parser: let a fixed-size array typedef declare an object (17284ab)

## 2026-10-03

* parser: take an unsized array's count from its initializer (7416e1e)
* test: pin the size a deduced array takes from its initializer (9af7d1d)
* ast: carry a bitfield member's bits in a member initializer (831fc9d)
* codegen: write a static bitfield initializer's own bits (2684e14)
* parser: read a signed brace-list constant's type from its operand (38b4f53)
* parser: place a brace initializer's values into bitfield members (4ff7f9e)
* parser: fold a bitfield's width and refuse one that is not positive
  (4acc502)
* codegen: test a bitfield brace initializer (e8b608f)
* parser: place a designated initializer's value into a bitfield member
  (1be30be)
* parser: address a part of an object in a static initializer (059477b)
* image: write absolute object data relocations with the part offset (330d53c)
* parser: store the address of a part of an object in a body's brace list
  (0ae2ee6)
* codegen: an array of aggregates reads as the address of its first element
  (2924959)
* parser: a member read on an element of a pointer goes through the general
  reader (66640ce)
* docs: an external linker may link what this compiler cannot read yet
  (91936cb)
* codegen: read a member through a pointer that is an array element (6f15212)
* codegen: widen a subscript index to a word before scaling it (deb6029)
* codegen: check a subscript through a pointer to an aggregate (dccaa91)
* cli: parse and document -external-linker (fa65e94)
* backend: name the external link's start files, loader and directories
  (ac88cc1)
* image: hand the final link to -external-linker (1426404)
* parser: read a cast or a parenthesized constant as a brace element (7c627e4)
* types: read a const-qualified aggregate as its unqualified type (ddc0750)
* parser: read GNU attributes in front of a declaration (0f7bd64)
* codegen: keep the alignment and the weak binding an attribute asks for
  (72b2158)
* parser: recover a brace list from its own start after a failed element
  (6563492)
* parser: read a compound assignment to a member or a dereference (febcd4a)
* codegen: write a compound assignment through one address (cef8443)
* parser: take a designated aggregate member as the element's value (fa829cf)
* codegen: copy an aggregate value into a struct member (e5dbde5)
* parser: give a conditional of two same structure or union arms that type
  (7a81737)
* codegen: convert between a function pointer and void * (10ac21b)
* codegen: materialize an aggregate conditional as a value (00ca4d2)
* parser: zero-fill an aggregate subobject a brace list does not write
  (1445f9e)
* parser: convert a function designator to a pointer as a cast operand
  (d758ba5)
* parser: name the whole type a conversion's destination is (cde1a96)
* types: promote an unnamed struct or union's members into the aggregate
  (b26bf42)
* standard: find a two-token spelling by comparing bytes (ed262e1)
* preprocess: hand a run back when nothing in it can expand (7c712c3)
* codegen: lay out every object the unit defines, not only the referenced
  ones (f8da57d)
* parser: record an unnamed struct or union member so its members are
  promoted (dd2d5d7)
* backend: the target comment names the paths that exist (5b4af1e)
* types: a decimal constant past every signed type is an unsigned 64-bit type
  (97c86d5)
* backend: a target holds the machine and the system as values (45f5e24)
* parser: refuse two members behind one name in an aggregate (b113994)
* parser: test that an anonymous member's members are found (98154e6)
* diagnostics: a class for a diagnostic the standard requires (4cbab95)
* parser: build a compound literal where its statement does not describe
  (e7017f8)
* parser: test a compound literal in a for header (6275398)
* backend: the machine carries its encoders as values a target calls (f3fe425)
* parser: a pointer to an array an alias names is a parameter this reader
  knows (1801e71)
* backend: the x86_64 module publishes its encoders as one value (7e9a27d)
* parser: an escape gcc does not know is the character itself (3d0811c)
* parser: sizeof does not evaluate a compound literal's operand (ace491d)
* backend: the composition reads the machine's encoders (2f4eded)
* github: the pinned V is one that has u128 (46e47ae)
* parser: a file-scope brace element is a constant expression (08c55e4)
* tools: the gate prints why a test failed, not only which file (c9763c1)
* parser: a compound literal initializes an aggregate object and its elements
  (3083e2e)
* codegen: the divide-by-zero test measures what the runner reports (8e4d878)
* diagnostics: a class for a discarded qualifier (c06c88e)
* types, parser: a conversion reason carries its diagnostic class (351ee88)
* codegen, parser, backend: the count-trailing builtins are the machine's bsf
  (1f318b8)
* codegen, parser, backend: the atomic builtins are the machine's
  instructions (6e72971)
* standard: the atomic and count-trailing builtins are a GNU row (52a4f6e)
* backend, parser: vfmt the encoder table and the builtin list (26210f6)
* codegen: the machine builtins evaluate their arguments at the call's depth
  (b5fa399)
* codegen: a call the unit does not declare is sized by its resolved type
  (106179c)
* parser, codegen: the machine builtins are tested on their answers (70fbfb6)
* standard: the C29 and C2y spellings name modes (f463293)
* standard, preprocess: every mode list carries C29 (d660c2e)
* codegen: an atomic value operand is converted to the target width (9555af3)
* codegen: the atomic operand conversion is tested (1723efd)
* tokenize: the trigraph measurement names the next standard's spellings
  (71478b0)
* types: a parameter's own qualifiers do not tell two function types apart
  (a96c90c)
* preprocess: the memory orders gcc predefines are predefined here (a1bfb23)
* parser, codegen: the dereference of a function designator is the designator
  (3ad97d1)
* parser, codegen: the statement-level asm is read and its barrier emitted
  (c36226d)
* codegen, parser, backend, standard: the count-leading builtins are bsr and
  xor (80def58)
* parser: a floating constant expression is a file-scope initializer (c1d91fd)
* parser: a cast in a file-scope initializer is an address constant (a629a6a)
* backend: a link is one of three shapes, and the argument list says which
  (434bd3b)
* cli: -shared and -static are spelled, and a link writes them (a118a99)
* backend: a program's link needs the compiler's own start file pair (9932cde)
* cli, main: -c beside -external-linker is a run with no link in it (fdda20d)
* codegen: a memory-class object argument is materialized once (504992d)
* codegen: a call of an object type is written into the temporary a value use
  needs (567fac9)
* types: a storage spelling carries no qualifiers (f4848a6)
* parser: a name nothing declares is the program's error, not a gap of this
  compiler (66c7f06)
* backend: a file-scope static name is a local symbol (30f37b0)
* codegen, backend: -fPIC reaches an object through the global offset table
  (9796dfa)
* parser, codegen, backend: a unit can reach an object another object defines
  (dcd838c)
* tests: -fPIC leaves a static object and a string constant as they are
  (062531b)
* codegen: a return without a value is read where C allows it (e889228)

## 2026-10-04

* backend: the x87 arithmetic and comparison a long double needs (d48bfc7)
* backend: name the class a long double travels in (77dca56)
* codegen: return a long double on the x87 stack (db6f22e)
* codegen: pass and read a long double in memory (f6516a1)
* codegen: compute and compare long doubles on the x87 stack (b03dbc1)
* parser: read a long double return and parameter (bf28f7d)
* codegen: test the long double calling convention end to end (ed4e360)
* codegen: give a call's stack bytes back only to the call that pushed them
  (2b7a8f3)
* codegen: test two long double calls in one argument list (59b1243)
* codegen,parser: carry long double _Complex through the back end (147f99f)
* codegen: a conversion to _Bool compares the value with zero (e4113e9)
* codegen,backend: a truth test on a long double compares it with zero
  (9375559)
* codegen: read an array-typed member as its address where it decays (93ef8f2)
* parser: keep a member path through a pointer reading through the pointer
  (661772a)
* parser: give a long-double builtin the extended value it names (2801406)
* parser: fold a constant condition of a conditional expression (885dba9)
* codegen: emit only the taken arm of a constant conditional (26a1060)
* backend: add the x87 negate the extended format needs (1d58484)
* codegen: compute unary minus on a long double with the x87 negate (1b1b472)
* readme: advertise (df2e2b0)
* tree: add the project logo (2a77a5d)
* docs: rewrite the README as an overview and a case for vcc (10f7651)
* cli: stop calling the compiler a stub in the version and the help (03bd89e)
* docs: fix image (00d9cd9)
* tree: round the logo's corners (798844e)
* docs: give the badges rounded corners (dd7915c)
* docs: fix (d62fa30)
* codegen: convert a conditional of complex arms to its complex type (218f2f2)
* codegen: define atexit as glibc's wrapper over __cxa_atexit (ebf2711)
* codegen: cover the atexit wrapper with its observable behaviour (45c5f82)
* tokenize: record whether whitespace preceded a token (f6a3fd4)
* preprocess: stringize writes the argument the way it was spelled (f049f87)
* parser: give a block-scope extern declaration no local storage (88b5610)
* parser: a file-scope long double keeps the value of its initializer
  (2430d12)
* backend: add the floating magnitude and fused multiply-add (081fcbc)
* codegen: emit the complex quotient with the scaled division (f8f1c52)
* codegen: make a conditional whose type is float a float value (14d2225)
* parser: register every declarator of a file-scope declaration (9c6150d)
* codegen: a program reads an object another object defines (784c2c7)
* tree: carry the C99 compliance corpus under compliance/ (c96a31b)
* tools: run the compliance corpus from a script (f4ec807)
* github: run the compliance corpus in CI (af3cbfb)
* types: keep an aggregate's layout on the type (2b841b5)
* parser: answer the static step-over from an index, not a walk (00dbbe2)
* tokenize: build token text in one buffer, not a character at a time
  (e78f08c)
* ast: hold a statement's member by pointer (a8a013c)
* ast: hold the part of a statement only some statements carry by pointer
  (74bdb14)
* docs: refresh the benchmark numbers (a169661)
* tree: rename the compliance corpus to monolithic.c (815e042)
* tree: add the compliance tests for sections 01 to 03 (aff9690)
* tree: add the compliance tests for sections 04 to 06 (daee420)
* tree: add the compliance tests for sections 07 to 11 (f8e2de0)
* tree: add the compliance tests for sections 12 to 14 (643c7f7)
* tree: add the compliance tests for sections 15 to 17 (b029988)
* tree: add the compliance tests for sections 18 and 19 (c75215e)
* tools: run every numbered compliance test (73975c8)
* docs: describe the compliance corpus as one test per check (da4bb87)
* github: run the compliance corpus on its own runner (740e9b1)
* docs: add a compliance tests badge to the README (85bd6f0)
* tools: add --count to the compliance runner (c72d204)
* github: keep the compliance badge count current (45ff3bc)
* tools: count the suite with tests.vsh (60b286a)
* github: keep the tests badge current (33bf730)
* docs: read the tests badge from the runner (28b385e)
* types: test the model's untested public surface (f1d0ada)
* ast: test the statement accessors and the boxed member (bceb0c2)
* printer: test the statement and expression shapes it prints (06e8943)
* optimizer: test the level spellings, the flag order and the folder (e3ebd58)
* diagnostics: test the class table, the mention order and the renderer
  (4ca15e9)
* standard: test the mode table's spellings and its order (8366a40)
* extensions: test the list flags, the mention order and the names (db85abd)
* tree: fill the compliance corpus to its last number (1460b52)
* types: test the aggregate layout and bitfield rules (4dec7a8)
* types: test the specifier table and the function-type rules (0f9ec06)
* cli: test the flag surface and the defaults (2c905ce)
* printer: test the clause the dump writes (c9e9d13)
* tokenize: test the pp-number and escape rules (a92e92b)
* preprocess: test the paste, stringize and conditional rules (3347f71)
* codegen: test the encodings and the relocations (b0fde9e)
* backend: test the container's sections and symbol entries (48a9418)
* docs: describe the architecture (79bca33)
* cli: take the version from v.mod at compile time (fdf5672)
* github: release when v.mod names a new version (92f8e76)
* tools: allow C in the test directories and nowhere else (570f11c)
* tree: say where C is allowed (02549f8)
* regression: pin forty fixed defects (794b7e5)
* goldens: compare a program's output byte for byte (43bbe24)
* tools: run the regression and golden corpora (5fcf4a9)
* github: keep the regression and tests badges current (0a67e3d)
* docker: build a reproducible vcc image (3f35a2b)
* docs: name the corpora, the badges and the runner (061dbe2)
* codegen: store a value narrower than the object it is assigned to (f30e7e9)
* parser: read a pointer subscript as the base of a member store (971d0c8)
* preprocess: join adjacent literals by their bytes, not their spellings
  (c187afc)
* tools: hold the regression corpus to its new count (e256553)
* github: count the new cases in the tests badge (5308b3e)
* tools: one front door over the build, the checks and the corpora (0cc7283)
* parser: initialize an array member from a string literal (97fa01d)
* tools: hold the regression corpus to its new count (708e892)
* github: count the new case in the tests badge (77791aa)
* github: rebase the badge jobs before they push (7edf9fd)
* github: count the new cases in the regressions badge (f6d1df7)
* tools: read a captured value from stdout alone (d3de432)
* tools: count the lines of non-test V the tree tracks (d7ab311)
* github: carry the line count in a badge (cedd4cc)
* docs: take the tree's size out of the prose (3025e40)
* tree: keep the Dockerfile out of the language composition (1c63b3d)

## 2026-10-05

* github: give the discussion surface one category per kind of post (42f9aef)
* github: publish the wiki from wiki/ on a push to main (bfc1597)
* docs: the wiki pages, published from wiki/ on a push to main (d503cd3)
