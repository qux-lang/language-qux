# language-qux

[![Project Status: WIP - Initial development is in progress, but there has not yet been a stable, usable release suitable for the public.](http://www.repostatus.org/badges/latest/wip.svg)](http://www.repostatus.org/#wip)
[![Build Status](https://travis-ci.org/hjwylde/language-qux.svg?branch=master)](https://travis-ci.org/hjwylde/language-qux)
[![Release](https://img.shields.io/github/release/hjwylde/language-qux.svg)](https://github.com/hjwylde/language-qux/releases)

Qux is an experimental language developed from the ground up with the aim of supporting extended
    static checks at compile time.
This package provides tools for working with it (parsing, compiling, pretty printing and type
    checking) within Haskell code.

If you're interested in actually compiling Qux files, see [here](https://github.com/hjwylde/qux) for
    the binary.

### Aims

Qux is designed as an imperative, functional programming language with extended static checks for
    program verification.
The goal is to be able to write pre- and post-conditions as part of type and method contracts that
    will be verifiable by mathematical means (e.g., a SMT solver or theorem prover).

Inspiration for a language with extended static checks has come from David J. Pearce's language,
    [Whiley](https://github.com/whiley "Whiley").
During my honours year I contributed a solution for verifying Whiley's method contracts using an
    external SMT solver (Z3).
For those interested in reading this rather long report, see
    [here](http://homepages.ecs.vuw.ac.nz/~djp/files/HenryWyldeENGR489.pdf).

### Tasks for v1

The language is in it's very initial stages of development and thus has very little features!
There are a few core tasks in mind that need to be achieved before v1 can come about:

* Key language features (assignment, strings, packages and imports).
* Compilation to LLVM.

Of course, there will be minor tasks to accompany this release, such as documentation on the language features.
The above merely mark the core functionality required.

### Tasks for v2

* Pre- and post-conditions on methods (using the `requires` and `ensures` keywords).
* Compilation and verification of method contracts.
* An intermediary language that retains contract information.
