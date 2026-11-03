"
I convert IEEE 754 double precision Floats to their shortest decimal representation using the Schubfach algorithm.

Raffaello Giulietti. The Schubfach way to render doubles. 2021.
Reference implementation: jdk.internal.math.DoubleToDecimal, used by Double.toString() since Java 19.

Unlike Ryu, which removes decimal digits one by one until the rounding interval no longer contains a shorter candidate, Schubfach picks the decimal exponent k so that at most one candidate needs to be examined beyond the two neighbours of the scaled value: it does three multiplications and a handful of comparisons, with no digit loop.

Examples:
	SchubfachPrinter print: 0.1.          ""'0.1'""
	SchubfachPrinter scientific: 1.0e23.  ""'1E23'""
	0.3 schubfachPrintString.             ""'0.3'""

The table of 126-bit approximations of powers of 10 is built in class initialization from exact integer arithmetic, and stored as 28-bit limbs so that the multiplications only use SmallIntegers.
"
Class {
	#name : 'SchubfachPrinter',
	#superclass : 'ShortestFloatPrinter',
	#classVars : [
		'Pow10'
	],
	#category : 'Ryu',
	#package : 'Ryu'
}

{ #category : 'class initialization' }
SchubfachPrinter class >> initialize [

	self initializeTables
]

{ #category : 'class initialization' }
SchubfachPrinter class >> initializeTables [
	"Pow10 at: e + 293 holds g = floor(beta) + 1, where 10^e = beta * 2^r and 2^125 <= beta < 2^126,
	for -292 <= e <= 324. This is g1 * 2^63 + g0 in jdk.internal.math.MathUtils."

	Pow10 := (-292 to: 324) collect: [ :e |
		| power bitLength |
		e >= 0
			ifTrue: [
				power := 10 raisedTo: e.
				bitLength := power highBit.
				self limbsOf: (power bitShift: 126 - bitLength) + 1 ]
			ifFalse: [
				power := 10 raisedTo: e negated.
				bitLength := power highBit.
				self limbsOf: (1 bitShift: 125 + bitLength) // power + 1 ] ]
]

{ #category : 'private' }
SchubfachPrinter >> decomposeMantissa: ieeeMantissa exponent: ieeeExponent [
	"Decode the Float as c * 2^q, toDecimal(double) in DoubleToDecimal.java"

	"DoubleToDecimal scales the subnormals with a mantissa below 3 by 10, because Java requires
	at least two digits (4.9E-324). They are not scaled here, to get the shortest representation (5E-324)."
	ieeeExponent = 0
		ifTrue: [ self decomposeSignificand: ieeeMantissa exponent: -1074 ]
		ifFalse: [ self decomposeSignificand: ieeeMantissa + 16r10000000000000 exponent: ieeeExponent - 1075 ].
	self removeTrailingZeros
]

{ #category : 'private' }
SchubfachPrinter >> decomposeSignificand: c exponent: q [
	"The core of the Schubfach algorithm, toDecimal(int, long, int) in DoubleToDecimal.java.
	Set digits and exponent for the value c * 2^q, possibly with trailing decimal zeros."

	| out cb cbl cbr k shift g vb vbl vbr s t sp10 tp10 upin wpin uin win cmp |
	out := c bitAnd: 1.
	cb := c bitShift: 2.
	cbr := cb + 2.
	(c ~= 16r10000000000000 or: [ q = -1074 ])
		ifTrue: [
			"Regular spacing"
			cbl := cb - 2.
			k := self floorLog10Pow2: q ]
		ifFalse: [
			"Irregular spacing: the lower neighbour is closer"
			cbl := cb - 1.
			k := self floorLog10ThreeQuartersPow2: q ].
	"vb, vbl and vbr are the scaled value and bounds c * 2^q * 10^-k * 4, rounded to odd.
	DoubleToDecimal shifts cb left by h = q + floor(log2(10^-k)) + 2 and keeps the upper bits of the product
	from bit 127, so the shift is 127 - h."
	shift := 125 - q - (self floorLog2Pow10: k negated).
	g := Pow10 at: k negated + 293.
	vb := self roundToOddMul: cb limbs: g shift: shift.
	vbl := self roundToOddMul: cbl limbs: g shift: shift.
	vbr := self roundToOddMul: cbr limbs: g shift: shift.
	s := vb bitShift: -2.
	s >= 10 ifTrue: [
		"Is one of the neighbouring multiples of 10 in the rounding interval?
		DoubleToDecimal only checks this for s >= 100, because Java prints at least two digits."
		sp10 := s // 10 * 10.
		tp10 := sp10 + 10.
		upin := vbl + out <= (sp10 bitShift: 2).
		wpin := (tp10 bitShift: 2) + out <= vbr.
		upin ~= wpin ifTrue: [
			^ self
				  digits: (upin ifTrue: [ sp10 ] ifFalse: [ tp10 ])
				  exponent: k ] ].
	"Is exactly one of s and t = s + 1 in the rounding interval?"
	t := s + 1.
	uin := vbl + out <= (s bitShift: 2).
	win := (t bitShift: 2) + out <= vbr.
	uin ~= win ifTrue: [
		^ self
			  digits: (uin ifTrue: [ s ] ifFalse: [ t ])
			  exponent: k ].
	"Both are in the rounding interval: take the one closest to the value, the even one on ties."
	cmp := vb - (s + t bitShift: 1).
	self
		digits: ((cmp < 0 or: [ cmp = 0 and: [ s even ] ])
				 ifTrue: [ s ]
				 ifFalse: [ t ])
		exponent: k
]

{ #category : 'private' }
SchubfachPrinter >> floorLog10Pow2: e [
	"Answer floor(log10(2^e)) for |e| <= 5456721"

	^ e * 661971961083 bitShift: -41
]

{ #category : 'private' }
SchubfachPrinter >> floorLog10ThreeQuartersPow2: e [
	"Answer floor(log10(3/4 * 2^e)) for |e| <= 2965827"

	^ e * 661971961083 - 274743187321 bitShift: -41
]

{ #category : 'private' }
SchubfachPrinter >> floorLog2Pow10: e [
	"Answer floor(log2(10^e)) for |e| <= 1838394"

	^ e * 913124641741 bitShift: -38
]

{ #category : 'private' }
SchubfachPrinter >> removeTrailingZeros [
	"digits is not zero and has at most 17 digits"

	| quotient |
	[ (quotient := digits // 100000000) * 100000000 = digits ] whileTrue: [
		digits := quotient.
		exponent := exponent + 8 ].
	(quotient := digits // 10000) * 10000 = digits ifTrue: [
		digits := quotient.
		exponent := exponent + 4 ].
	(quotient := digits // 100) * 100 = digits ifTrue: [
		digits := quotient.
		exponent := exponent + 2 ].
	(quotient := digits // 10) * 10 = digits ifTrue: [
		digits := quotient.
		exponent := exponent + 1 ]
]

{ #category : 'private' }
SchubfachPrinter >> roundToOddMul: m limbs: limbs shift: shift [
	"Answer (m * multiplier) >> shift, with its lowest bit set when some of the shifted out bits are not zero,
	where multiplier < 2^140 is given as five 28-bit limbs. This is rop() in DoubleToDecimal.java.
	Like rop(), it ignores the lowest 64 - h = shift - 63 bits of the product: the table entries are
	approximations by excess, and their error must not set the lowest bit. rop() computes
	floor(g1 * cp / 2) + floor(g0 * cp / 2^64) where cp = m * 2^h is even, which is floor(g * cp / 2^64).
	As in RyuPrinter>>#mulShift:limbs:shift:, splitting m < 2^56 into two 28-bit limbs keeps every
	partial product and column sum within SmallInteger range. Schubfach only uses shifts in [122, 125]."

	| m0 m1 a0 a1 a2 a3 a4 column sticky r4 r5 bits result |
	m0 := m bitAnd: 16rFFFFFFF.
	m1 := m bitShift: -28.
	a0 := limbs at: 1.
	a1 := limbs at: 2.
	a2 := limbs at: 3.
	a3 := limbs at: 4.
	a4 := limbs at: 5.
	column := m0 * a0 bitShift: -28.
	column := m0 * a1 + (m1 * a0) + column bitShift: -28.
	column := m0 * a2 + (m1 * a1) + column.
	"Bits 56 to 83 of the product: keep those from bit shift - 63 for the sticky bit"
	sticky := (column bitAnd: 16rFFFFFFF) bitShift: 119 - shift.
	column := m0 * a3 + (m1 * a2) + (column bitShift: -28).
	sticky := sticky bitOr: (column bitAnd: 16rFFFFFFF).
	column := m0 * a4 + (m1 * a3) + (column bitShift: -28).
	r4 := column bitAnd: 16rFFFFFFF.
	column := m1 * a4 + (column bitShift: -28).
	r5 := column bitAnd: 16rFFFFFFF.
	bits := shift - 112.
	sticky := sticky bitOr: (r4 bitAnd: (1 bitShift: bits) - 1).
	result := (r4 bitShift: bits negated) + (r5 bitShift: 28 - bits) + ((column bitShift: -28) bitShift: 56 - bits).
	^ sticky = 0
		  ifTrue: [ result ]
		  ifFalse: [ result bitOr: 1 ]
]
