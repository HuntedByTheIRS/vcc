module main

import backend
import cli
import codegen
import optimizer
import os
import parser
import preprocess
import tokenize

// -verbose reports what the compiler is doing and must change nothing about what
// it compiles. The report is checked as the lines each stage hands back, and the
// image bytes are the claim that the flag is a report and not a behaviour.
//
// gcc's -v prints the cc1, as and collect2 command lines it runs. This compiler
// runs none of them: it emits the container itself, so what it can honestly
// report is the phases and what the file will carry.

fn verbose_scratch(name string) string {
	return os.join_path(os.temp_dir(), 'vcc_verbose_test_${os.getpid()}_${name}')
}

fn verbose_image(args []string, source string) codegen.Result {
	opts := cli.parse(args) or { panic(err) }
	lexed := tokenize.lex(os.read_file(source) or { '' })
	parsed := parser.parse(lexed.tokens)
	optimized := optimizer.optimize(parsed.unit, opts.optimization)
	return codegen.emit(optimized, codegen.Options{
		target:       opts.target
		entry:        'main'
		libraries:    opts.libraries
		library_dirs: opts.library_dirs
	})
}

fn test_the_header_names_this_compiler_and_its_target() {
	host := backend.host() or { panic('this test needs the host target') }
	opts := cli.parse(['-verbose', '-std=gnu11', 'x.c'])!
	lines := verbose_header_lines(opts)
	assert lines.len == 3
	assert lines[0] == 'vcc version ${cli.version} (pure V)'
	assert lines[1] == 'target: ${host.name}'
	assert lines[2].starts_with('standard: gnu11')
}

fn test_the_include_lines_are_the_search_in_order() {
	opts := cli.parse(['-verbose', '-I/opt/one', 'x.c'])!
	lines := verbose_include_dir_lines(opts)
	assert lines[0] == 'include: /opt/one'
	assert lines[lines.len - 1] == 'include: /usr/include (standard)'
	// -nostdinc takes the standard directories out and says so, rather than
	// printing an empty search.
	off := cli.parse(['-verbose', '-nostdinc', 'x.c'])!
	without := verbose_include_dir_lines(off)
	assert without.len == 1
	assert without[0].contains('-nostdinc')
}

fn test_the_read_lines_name_the_files_the_read_opened() {
	opts := cli.parse(['-verbose', 'x.c'])!
	files := [
		preprocess.SourceFile{
			path: '/tmp/a.c'
		},
		preprocess.SourceFile{
			path:   '/usr/include/stdio.h'
			system: true
		},
	]
	assert verbose_file_lines(files) == ['read: /tmp/a.c', 'read: /usr/include/stdio.h (system)']
}

fn test_the_result_lines_name_the_work_this_compiler_does_itself() {
	host := backend.host() or { panic('this test needs the host target') }
	source := verbose_scratch('result.c')
	os.write_file(source, 'int main(void) { return 1; }\n') or { panic(err) }
	defer {
		os.rm(source) or {}
	}
	opts := cli.parse(['-verbose', '-lm'])!
	image := verbose_image([source, '-o', verbose_scratch('result')], source)
	assert image.diagnostics.len == 0
	lines := verbose_result_lines(opts, [cli.Phase{
		name:   'emit'
		micros: 5
	}], image.bytes, '/tmp/out')
	assert lines[0] == 'phase: emit 5us'
	assert lines.contains('link: no linker is run; this compiler writes the container itself')
	assert lines.contains('  interpreter: ${host.interpreter}')
	assert lines.contains('  library: ${host.base_library()} (the C library every image names)')
	// The -l name is resolved here the same way the link resolves it, so the
	// report cannot name a library the image would not.
	assert lines.any(it.starts_with('  library: libm.so'))
	assert lines.any(it.starts_with('  written: /tmp/out ('))
}

fn test_verbose_changes_no_image_bytes() {
	source := verbose_scratch('verbose.c')
	os.write_file(source, 'int main(void) { return 5; }\n') or { panic(err) }
	defer {
		os.rm(source) or {}
	}
	plain := verbose_image([source, '-o', verbose_scratch('plain')], source)
	talky := verbose_image([source, '-o', verbose_scratch('talky'), '-verbose'], source)
	assert talky.diagnostics.len == 0
	assert talky.bytes == plain.bytes
}
