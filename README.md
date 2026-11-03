# Ryu, Schubfach and Dragonbox for Pharo

Shortest, round-trip float-to-string conversion for Pharo, with three algorithms:

- **Ryu**, ported from [ulfjack/ryu](https://github.com/ulfjack/ryu) (`d2s.c`, full-table variant).
  > Ulf Adams. 2018. *Ryū: fast float-to-string conversion.* PLDI 2018.
- **Schubfach**, ported from `jdk.internal.math.DoubleToDecimal`, which `Double.toString()` has used since Java 19.
  > Raffaello Giulietti. 2021. *The Schubfach way to render doubles.*
- **Dragonbox**, ported from [jk-jeon/dragonbox](https://github.com/jk-jeon/dragonbox) (`dragonbox.h`,
  nearest-to-even rounding), which {fmt} and `std::format` use.
  > Junekey Jeon. 2020. *Dragonbox: A New Floating-Point Binary-to-Decimal Conversion Algorithm.*

All three give exactly the same results (cross-checked on 11 million doubles). Dragonbox is the
fastest: about 2.3x faster than Schubfach and 3x faster than Ryu for the conversion itself.

## Loading

```smalltalk
Metacello new
	baseline: 'Ryu';
	repository: 'github://SergeStinckwich/pharo-ryu:main/src';
	load.
```

Groups: `Core` (just `Ryu`), `Tests`, `default` (everything, including benchmarks).

## Usage

`RyuPrinter`, `SchubfachPrinter` and `DragonboxPrinter` have the same API, inherited from `ShortestFloatPrinter`:

```smalltalk
DragonboxPrinter print: 0.1.          "'0.1'      same format as Float>>#printString"
DragonboxPrinter scientific: 1.0e23.  "'1E23'     same format as d2s() in the Ryu C library"
RyuPrinter print: 0.1.                "'0.1'"
0.3 dragonboxPrintString.             "'0.3'"
0.3 schubfachPrintString.             "'0.3'"
0.3 ryuPrintString.                   "'0.3'"
1.5e-7 ryuScientificString.           "'1.5E-7'"
(DragonboxPrinter new decompose: 123.456; yourself) digits.   "123456 (exponent -3)"

"Make every base 10 Float>>#printString use Ryu for a dynamic extent"
FloatPrintPolicy value: RyuFloatPrintPolicy new during: [ 0.1 printString ].
```

## Differences with `Float>>#printString`

Both give the shortest string that reads back to the same Float. When the exact
binary value lies exactly halfway between two shortest candidates, the three printers
round half to even (like their reference implementations), while `printString` rounds half up:

```smalltalk
2.98023223876953125e-8 printString.     "'2.9802322387695313e-8'"
2.98023223876953125e-8 ryuPrintString.  "'2.9802322387695312e-8'"
```

This affected 258 of 1,000,000 random bit patterns.

## Implementation notes

- The tables (powers of 5 for Ryu, 126-bit approximations of powers of 10 for Schubfach,
  128-bit approximations rounded up for Dragonbox) are computed at class initialization with exact integer arithmetic, and stored as
  five 28-bit limbs per entry.
- The 64x128-bit multiplications use only SmallInteger arithmetic: with 28-bit limbs,
  every partial product fits in a 61-bit SmallInteger. Ryu only uses shifts in 118..125,
  Schubfach in 122..125 and Dragonbox in 119..122, so only the top three limbs of the product are needed.
- Dragonbox's scaled upper bound `zi` can reach 2^64, beyond the SmallInteger range (2^60).
  It is kept in two parts and divided by 1000 without building it: building it made
  Dragonbox slower than Schubfach because of LargePositiveInteger arithmetic.
- Schubfach differs from the Java code in two places, because Java prints at least two
  digits (`4.9E-324`) where we want the shortest (`5E-324`):
  - the smallest subnormals are not scaled by 10;
  - one more digit is removed whenever `s >= 10`, not only when `s >= 100`.
- Like Java's `rop()`, Schubfach's round-to-odd multiplication ignores the lowest 64 bits
  of the product, where the error of the approximated powers of 10 lives. Taking them into
  account gives wrong (17-digit) results for some integers like `5.5601447768750624e16`.

## Tests

`ShortestFloatPrinterTest` is abstract. `RyuPrinterTest` (20 tests), `SchubfachPrinterTest`
(22 tests) and `DragonboxPrinterTest` (22 tests) run its tests on their printer. They cover:

- the reference cases from the Ryu C library's `d2s_test.cc`
- agreement with `Float>>#printString` on integral values, all powers of two,
  subnormals, short decimals and random bit patterns (ties checked to be exact halfway
  points)
- round trip through `Number readFrom:` in both formats
- for Schubfach and Dragonbox, identical digits and exponent as Ryu for every exponent (smallest,
  middle and largest mantissas) and 100,000 random bit patterns

## Benchmarks

```smalltalk
RyuBenchmark run.
RyuBenchmark new size: 5000; repetitions: 3; run.
```

Pharo 14, 64-bit, Apple Silicon. Results are ns per conversion, best of 5 runs over 10,000 floats.

Conversion to a String:

| dataset             | printString | inexact |  Ryu | Schubfach | Dragonbox | Dragonbox speedup |
|---------------------|------------:|--------:|-----:|----------:|----------:|------------------:|
| random bit patterns |       23414 |    1423 |  895 |       789 |       629 |             37.2x |
| uniform [0, 1)      |        1273 |    1029 |  788 |       782 |       639 |              2.0x |
| integral values     |         661 |     595 |  443 |       450 |       461 |              1.4x |
| two decimals        |         622 |     515 |  667 |       574 |       460 |              1.4x |
| large and tiny      |       23757 |    1447 | 1127 |       778 |       653 |             36.4x |

Shortest decimal only (`decompose:`, without the formatting all printers share):

| dataset             | Ryu | Schubfach | Dragonbox | Dragonbox vs Ryu | Dragonbox vs Schubfach |
|---------------------|----:|----------:|----------:|-----------------:|-----------------------:|
| random bit patterns | 347 |       262 |       108 |             3.2x |                   2.4x |
| uniform [0, 1)      | 240 |       235 |        97 |             2.5x |                   2.4x |
| integral values     |  23 |        26 |        28 |             0.8x |                   0.9x |
| two decimals        | 296 |       240 |       111 |             2.7x |                   2.2x |
| large and tiny      | 613 |       246 |       110 |             5.6x |                   2.2x |

`inexact` is `absPrintInexactlyOn:base:`, which is faster than `printString` but doesn't
always give the shortest string. Integral values take a shared fast path in all printers.
Formatting (about 500 ns) now costs much more than the algorithms themselves.

## License

MIT, see [LICENSE](LICENSE). The Ryu printer is a port of [ulfjack/ryu](https://github.com/ulfjack/ryu),
by Ulf Adams, available under the Apache License 2.0 or the Boost Software License 1.0. The Schubfach
printer is a port of `DoubleToDecimal` from OpenJDK, by Raffaello Giulietti. The Dragonbox printer
is a port of [jk-jeon/dragonbox](https://github.com/jk-jeon/dragonbox), by Junekey Jeon, available
under the Apache License 2.0 with LLVM Exceptions or the Boost Software License 1.0.
