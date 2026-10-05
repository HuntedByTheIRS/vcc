module output

import backend
import backend.os.elf
import image as unit

// Wrapping a merged program as the bytes of an output file. It is a seam and
// deliberately thin: the container in backend/os/elf writes the shape a program
// has today, and the second shape a link will need (the start files, a procedure
// linkage table, an ld-shaped command line) belongs here as another function
// rather than as a change to the merge. The `image` module is imported under
// another name because this function is named for what it returns, and the name
// would otherwise shadow the module its argument's type is written from.
pub fn image(program unit.Program, target backend.Target) ![]u8 {
	return elf.executable(program, target)
}
