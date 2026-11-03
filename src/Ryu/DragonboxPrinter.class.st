"
I convert IEEE 754 double precision Floats to their shortest decimal representation using the Dragonbox algorithm.

Junekey Jeon. 2020. Dragonbox: A New Floating-Point Binary-to-Decimal Conversion Algorithm.
Reference implementation: https://github.com/jk-jeon/dragonbox (dragonbox.h, nearest-to-even rounding, used by {fmt} and std::format).

Dragonbox builds on Schubfach: it picks a decimal exponent so that the rounding interval, scaled by a power of 10, has a width between 100 and 1000. In the common case a single multiplication gives the scaled upper bound zi, and dividing it by 1000 gives the answer, or by 100 when the larger divisor fails. Ryu and Schubfach need three multiplications (value and both bounds); Dragonbox only needs more for the parity of the lower bound or of the value in rare cases.

Examples:
	DragonboxPrinter print: 0.1.          ""'0.1'""
	DragonboxPrinter scientific: 1.0e23.  ""'1E23'""
	0.3 dragonboxPrintString.             ""'0.3'""

The table of 128-bit approximations of powers of 10, rounded up, is built in class initialization from exact integer arithmetic, and stored as 28-bit limbs so that the multiplications only use SmallIntegers.

The integer part of the products may exceed the SmallInteger range (2^60), so it is kept in two parts, productHigh * 2^productShift + productLow, and divided by 1000 without building it.

Instance Variables
	productHigh:	<SmallInteger> high part of the integer part of the last product computed by #mulCache:limbs:beta:
	productIsInteger:	<Boolean> whether the last product had no fractional part
	productLow:	<SmallInteger> low part of the integer part of the last product
	productShift:	<SmallInteger> number of bits of productLow
"
Class {
	#name : 'DragonboxPrinter',
	#superclass : 'ShortestFloatPrinter',
	#instVars : [
		'productHigh',
		'productIsInteger',
		'productLow',
		'productShift'
	],
	#classVars : [
		'Cache'
	],
	#category : 'Ryu',
	#package : 'Ryu'
}

{ #category : 'class initialization' }
DragonboxPrinter class >> initialize [

	self initializeTables
]

{ #category : 'class initialization' }
DragonboxPrinter class >> initializeTables [
	"Cache at: k + 293 holds ceiling(10^k * 2^(127 - floor(log2(10^k)))), in [2^127, 2^128),
	for -292 <= k <= 326. This is cache_holder<ieee754_binary64>::cache in dragonbox.h."

	Cache := (-292 to: 326) collect: [ :k |
		| power bitLength |
		power := 10 raisedTo: k abs.
		bitLength := power highBit.
		self limbsOf: (k >= 0
				 ifTrue: [
					 bitLength <= 128
						 ifTrue: [ power bitShift: 128 - bitLength ]
						 ifFalse: [ (power + (1 bitShift: bitLength - 128) - 1) bitShift: 128 - bitLength ] ]
				 ifFalse: [ (1 bitShift: 127 + bitLength) + power - 1 // power ]) ]
]

{ #category : 'private' }
DragonboxPrinter >> cacheHighOf: limbs [
	"Answer the 64 most significant bits of the 128-bit cache entry"

	^ ((limbs at: 5) bitShift: 48) + ((limbs at: 4) bitShift: 20) + ((limbs at: 3) bitShift: -8)
]

{ #category : 'private' }
DragonboxPrinter >> decomposeMantissa: ieeeMantissa exponent: ieeeExponent [
	"compute_nearest_normal() in dragonbox.h. The value is twoFc * 2^(e - 1)."

	| e twoFc includeEndpoints minusK limbs beta deltai isZInteger power quotient low significand remainder smallDivisor dist approxYParity divisible |
	ieeeExponent = 0
		ifTrue: [
			e := -1074.
			twoFc := ieeeMantissa * 2 ]
		ifFalse: [
			e := ieeeExponent - 1075.
			ieeeMantissa = 0 ifTrue: [ ^ self decomposeShorterInterval: e ].
			twoFc := ieeeMantissa + 16r10000000000000 * 2 ].
	"Nearest to even: the bounds of the rounding interval are included when the significand is even"
	includeEndpoints := (twoFc bitAnd: 2) = 0.

	"Step 1: Schubfach multiplier calculation. 10^kappa <= deltai < 10^(kappa + 1), with kappa = 2."
	minusK := (self floorLog10Pow2: e) - 2.
	limbs := Cache at: minusK negated + 293.
	beta := e + (self floorLog2Pow10: minusK negated).
	deltai := (limbs at: 5) bitShift: beta - 15.
	self mulCache: (twoFc bitOr: 1) limbs: limbs beta: beta.
	isZInteger := productIsInteger.

	"Step 2: try the larger divisor 10^(kappa + 1).
	significand := zi // 1000 and remainder := zi \\ 1000, where zi = productHigh * 2^productShift + productLow"
	power := 1 bitShift: productShift.
	quotient := power // 1000.
	low := productHigh * (power - (quotient * 1000)) + productLow.
	significand := productHigh * quotient + (low // 1000).
	remainder := low \\ 1000.
	smallDivisor := remainder > deltai.
	remainder < deltai ifTrue: [
		"Exclude the right endpoint if necessary"
		(remainder = 0 and: [ isZInteger and: [ includeEndpoints not ] ]) ifTrue: [
			significand := significand - 1.
			remainder := 1000.
			smallDivisor := true ] ].
	remainder = deltai ifTrue: [
		"Compare the fractional parts of the left endpoint and of deltai"
		self mulCache: twoFc - 1 limbs: limbs beta: beta.
		(productLow odd or: [
			 productIsInteger and: [ includeEndpoints ] ]) ifFalse: [ smallDivisor := true ] ].
	smallDivisor ifFalse: [
		digits := significand.
		exponent := minusK + 3.
		^ self removeTrailingZeros ].

	"Step 3: find the significand with the smaller divisor 10^kappa"
	significand := significand * 10.
	dist := remainder - (deltai bitShift: -1) + 50.
	approxYParity := ((dist bitXor: 50) bitAnd: 1) = 1.
	divisible := dist \\ 100 = 0.
	significand := significand + (dist // 100).
	divisible ifTrue: [
		"y is either zi - epsiloni or one less: their parities tell which"
		self mulCache: twoFc limbs: limbs beta: beta.
		productLow odd = approxYParity
			ifTrue: [
				"On a tie, when y is an integer, round to even"
				(productIsInteger and: [ significand odd ]) ifTrue: [ significand := significand - 1 ] ]
			ifFalse: [ significand := significand - 1 ] ].
	digits := significand.
	exponent := minusK + 2
]

{ #category : 'private' }
DragonboxPrinter >> decomposeShorterInterval: e [
	"compute_nearest_shorter() in dragonbox.h, for a Float 2^52 * 2^e whose lower neighbour is closer
	than its upper neighbour. Both endpoints are included since the significand is even."

	| minusK beta cacheHigh xi zi significand |
	minusK := self floorLog10Pow2MinusLog10FourThirds: e.
	beta := e + (self floorLog2Pow10: minusK negated).
	cacheHigh := self cacheHighOf: (Cache at: minusK negated + 293).
	xi := cacheHigh - (cacheHigh bitShift: -54) bitShift: beta - 11.
	zi := cacheHigh + (cacheHigh bitShift: -53) bitShift: beta - 11.
	"The left endpoint is an integer only for e = 2 and e = 3"
	(e between: 2 and: 3) ifFalse: [ xi := xi + 1 ].
	"Try the bigger divisor"
	significand := zi // 10.
	significand * 10 >= xi ifTrue: [
		digits := significand.
		exponent := minusK + 1.
		^ self removeTrailingZeros ].
	"Otherwise, round y up; the only tie happens for e = -77"
	significand := (cacheHigh bitShift: beta - 10) + 1 // 2.
	(significand odd and: [ e = -77 ])
		ifTrue: [ significand := significand - 1 ]
		ifFalse: [ significand < xi ifTrue: [ significand := significand + 1 ] ].
	digits := significand.
	exponent := minusK
]

{ #category : 'private' }
DragonboxPrinter >> floorLog10Pow2: e [
	"Answer floor(log10(2^e)) for |e| <= 1700"

	^ e * 315653 bitShift: -20
]

{ #category : 'private' }
DragonboxPrinter >> floorLog10Pow2MinusLog10FourThirds: e [
	"Answer floor(log10(2^e) - log10(4/3)) for |e| <= 1700"

	^ e * 631305 - 261663 bitShift: -21
]

{ #category : 'private' }
DragonboxPrinter >> floorLog2Pow10: e [
	"Answer floor(log2(10^e)) for |e| <= 1233"

	^ e * 1741647 bitShift: -19
]

{ #category : 'private' }
DragonboxPrinter >> mulCache: m limbs: limbs beta: beta [
	"Compute the integer part of m * 2^beta * cache / 2^128 in productHigh, productShift and productLow,
	and set productIsInteger to whether its next 64 fractional bits are zero. This is compute_mul() and compute_mul_parity() in
	dragonbox.h, which compute the upper or lower 128 bits of the 192-bit product of a 64-bit
	integer with the 128-bit cache entry.
	As in RyuPrinter>>#mulShift:limbs:shift:, splitting m < 2^56 into two 28-bit limbs keeps every
	partial product and column sum within SmallInteger range. Dragonbox only uses beta in [6, 9]."

	| m0 m1 a0 a1 a2 a3 a4 column r1 r2 r3 r4 r5 cut bits |
	m0 := m bitAnd: 16rFFFFFFF.
	m1 := m bitShift: -28.
	a0 := limbs at: 1.
	a1 := limbs at: 2.
	a2 := limbs at: 3.
	a3 := limbs at: 4.
	a4 := limbs at: 5.
	column := m0 * a0 bitShift: -28.
	column := m0 * a1 + (m1 * a0) + column.
	r1 := column bitAnd: 16rFFFFFFF.
	column := m0 * a2 + (m1 * a1) + (column bitShift: -28).
	r2 := column bitAnd: 16rFFFFFFF.
	column := m0 * a3 + (m1 * a2) + (column bitShift: -28).
	r3 := column bitAnd: 16rFFFFFFF.
	column := m0 * a4 + (m1 * a3) + (column bitShift: -28).
	r4 := column bitAnd: 16rFFFFFFF.
	column := m1 * a4 + (column bitShift: -28).
	r5 := column bitAnd: 16rFFFFFFF.
	"The integer part starts at bit 128 - beta of m * cache, the fractional bits checked start at bit 64 - beta.
	Shifting r1 and r2 left or right by the distance between their position and the cut keeps exactly the
	bits above the cut, or adds zeros, which does not change the test against zero."
	cut := 64 - beta.
	bits := 16 - beta.
	productIsInteger := ((r1 bitShift: 28 - cut) bitOr: (r2 bitShift: 56 - cut)) = 0 and: [
		                    r3 = 0 and: [ (r4 bitAnd: (1 bitShift: bits) - 1) = 0 ] ].
	productShift := 56 - bits.
	productLow := (r4 bitShift: bits negated) + (r5 bitShift: 28 - bits).
	productHigh := column bitShift: -28
]
