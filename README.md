# Ryu for Pharo

Shortest, round-trip float-to-string conversion for Pharo, ported from
[ulfjack/ryu](https://github.com/ulfjack/ryu) (`d2s.c`, full-table variant).

> Ulf Adams. 2018. *Ryū: fast float-to-string conversion.* PLDI 2018.

## Loading

```smalltalk
Metacello new
	baseline: 'Ryu';
	repository: 'github://SergeStinckwich/pharo-ryu:main/src';
	load.
```

Groups: `Core` (just `Ryu`), `Tests`, `default` (everything, including benchmarks).

## Usage

```smalltalk
RyuPrinter print: 0.1.            "'0.1'      same format as Float>>#printString"
RyuPrinter scientific: 1.0e23.    "'1E23'     same format as d2s() in the C library"
0.3 ryuPrintString.               "'0.3'"
1.5e-7 ryuScientificString.       "'1.5E-7'"
(RyuPrinter new decompose: 123.456; yourself) digits.   "123456 (exponent -3)"

"Make every base 10 Float>>#printString use Ryu for a dynamic extent"
FloatPrintPolicy value: RyuFloatPrintPolicy new during: [ 0.1 printString ].
```

## Differences with `Float>>#printString`

Both give the shortest string that reads back to the same Float. When the exact
binary value lies exactly halfway between two shortest candidates, Ryu rounds half
to even (like the C reference) and `printString` rounds half up:

```smalltalk
2.98023223876953125e-8 printString.     "'2.9802322387695313e-8'"
2.98023223876953125e-8 ryuPrintString.  "'2.9802322387695312e-8'"
```

This affected 258 of 1,000,000 random bit patterns.

## Implementation notes

- The tables of powers of 5 are computed at class initialization with exact integer
  arithmetic, and stored as five 28-bit limbs per entry.
- The 64x128-bit multiplications of the C code (`mulShift64`) use only SmallInteger
  arithmetic: with 28-bit limbs, every partial product fits in a 61-bit SmallInteger.
  Ryu only uses shifts in 118..125, so only the top three limbs of the product are needed.

## Tests

`RyuPrinterTest` (20 tests) covers:

- the reference cases from the C library's `d2s_test.cc`
- agreement with `Float>>#printString` on integral values, all powers of two,
  subnormals, short decimals and random bit patterns (ties checked to be exact halfway
  points)
- round trip through `Number readFrom:` in both formats

## Benchmarks

```smalltalk
RyuBenchmark run.
RyuBenchmark new size: 5000; repetitions: 3; run.
```

Pharo 14, 64-bit, Apple Silicon. Results are ns per conversion, best of 5 runs over 10,000 floats:

| dataset             | printString | inexact | Ryu | Ryu E | speedup |
|---------------------|------------:|--------:|----:|------:|--------:|
| random bit patterns |       22254 |    1422 | 815 |   803 |   27.3x |
| uniform [0, 1)      |        1265 |    1030 | 760 |   690 |    1.7x |
| integral values     |         679 |     578 | 444 |   367 |    1.5x |
| two decimals        |         637 |     534 | 629 |   665 |    1.0x |
| large and tiny      |       22579 |    1368 |1093 |  1071 |   20.7x |

`inexact` is `absPrintInexactlyOn:base:`, which is faster than `printString` but doesn't
always give the shortest string. `Ryu E` is the scientific format.

## License

MIT, see [LICENSE](LICENSE). This is a port of [ulfjack/ryu](https://github.com/ulfjack/ryu),
by Ulf Adams, which is available under the Apache License 2.0 or the Boost Software License 1.0.
