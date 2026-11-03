"
I convert IEEE 754 double precision Floats to their shortest decimal representation using the Ryu algorithm.

Ulf Adams. 2018. Ryū: fast float-to-string conversion. PLDI 2018. https://doi.org/10.1145/3192366.3192369
Reference implementation: https://github.com/ulfjack/ryu (this is a port of d2s.c, full table variant).

The output is the shortest digit string that reads back to exactly the same Float; when several such strings exist, the one closest to the exact binary value is chosen, with ties rounded half to even like the C reference.
Float>>#printString rounds such ties half up, so both differ in the last digit for a few values, e.g. 2.98023223876953125e-8: '2.9802322387695312e-8' here, '2.9802322387695313e-8' for printString. Both are shortest and read back to the same Float.

Two output formats are provided:
- Pharo format, identical to Float>>#printString (e.g. '0.1', '100.0', '1.0e23', 'Float nan')
- Ryu scientific format, identical to d2s() from the C reference implementation (e.g. '1E-1', '1E2', '1E23', 'NaN')

Examples:
	RyuPrinter print: 0.1.          ""'0.1'""
	RyuPrinter scientific: 1.0e23.  ""'1E23'""
	0.3 ryuPrintString.             ""'0.3'""

	(RyuPrinter new decompose: 123.456; yourself) digits. ""123456""

The tables of powers of 5 are built in class initialization from exact integer arithmetic, and stored as 28-bit limbs so that the 128-bit multiplications of the reference implementation only use SmallIntegers.

Instance Variables
	digits:	<Integer> decimal significand of the last decomposed Float
	exponent:	<Integer> power of ten of the last decomposed Float, value = digits * (10 raisedTo: exponent)
"
Class {
	#name : 'RyuPrinter',
	#superclass : 'Object',
	#instVars : [
		'digits',
		'exponent'
	],
	#classVars : [
		'Pow5InvSplit',
		'Pow5Split'
	],
	#category : 'Ryu',
	#package : 'Ryu'
}

{ #category : 'class initialization' }
RyuPrinter class >> initialize [

	self initializeTables
]

{ #category : 'class initialization' }
RyuPrinter class >> initializeTables [
	"Pow5Split at: i + 1 holds the 125 most significant bits of 5^i.
	Pow5InvSplit at: i + 1 holds floor(2^(log2(5^i) + 125) / 5^i) + 1.
	These are DOUBLE_POW5_SPLIT and DOUBLE_POW5_INV_SPLIT from d2s_full_table.h,
	stored as 28-bit limbs (see #mulShift:limbs:shift:)."

	| pow5 bitLength |
	Pow5Split := Array new: 326.
	Pow5InvSplit := Array new: 342.
	pow5 := 1.
	0 to: 341 do: [ :i |
		bitLength := pow5 highBit.
		i < 326 ifTrue: [ Pow5Split at: i + 1 put: (self limbsOf: (pow5 bitShift: 125 - bitLength)) ].
		Pow5InvSplit at: i + 1 put: (self limbsOf: (1 bitShift: bitLength - 1 + 125) // pow5 + 1).
		pow5 := pow5 * 5 ]
]

{ #category : 'class initialization' }
RyuPrinter class >> limbsOf: anInteger [
	"Answer the five 28-bit limbs of anInteger < 2^140, least significant first"

	^ (0 to: 4) collect: [ :i | (anInteger bitShift: i * -28) bitAnd: 16rFFFFFFF ]
]

{ #category : 'printing' }
RyuPrinter class >> print: aFloat [
	"Answer the shortest decimal representation of aFloat, formatted like Float>>#printString"

	^ String new: 24 streamContents: [ :stream | self new print: aFloat on: stream ]
]

{ #category : 'printing' }
RyuPrinter class >> print: aFloat on: aStream [

	self new print: aFloat on: aStream
]

{ #category : 'printing' }
RyuPrinter class >> scientific: aFloat [
	"Answer the shortest decimal representation of aFloat, formatted like d2s() of the Ryu C library"

	^ String new: 24 streamContents: [ :stream | self new printScientific: aFloat on: stream ]
]

{ #category : 'private' }
RyuPrinter >> decimalLength: anInteger [

	| length power |
	length := 1.
	power := 10.
	[ anInteger >= power ] whileTrue: [
		length := length + 1.
		power := power * 10 ].
	^ length
]

{ #category : 'converting' }
RyuPrinter >> decompose: aFloat [
	"Set digits and exponent to the shortest decimal representation of the absolute value of aFloat.
	aFloat must be finite."

	| high ieeeExponent ieeeMantissa |
	high := aFloat basicAt: 1.
	ieeeExponent := (high bitShift: -20) bitAnd: 16r7FF.
	ieeeExponent = 16r7FF ifTrue: [ ^ self error: 'Cannot decompose NaN or infinite Float' ].
	ieeeMantissa := ((high bitAnd: 16rFFFFF) bitShift: 32) + (aFloat basicAt: 2).
	(ieeeExponent = 0 and: [ ieeeMantissa = 0 ]) ifTrue: [
		digits := 0.
		exponent := 0.
		^ self ].
	(self decomposeSmallIntegerMantissa: ieeeMantissa exponent: ieeeExponent) ifTrue: [ ^ self ].
	self decomposeMantissa: ieeeMantissa exponent: ieeeExponent
]

{ #category : 'private' }
RyuPrinter >> decomposeMantissa: ieeeMantissa exponent: ieeeExponent [
	"The core of the Ryu algorithm, d2d() in d2s.c"

	| e2 m2 acceptBounds mv mmShift vr vp vm e10 vmIsTrailingZeros vrIsTrailingZeros q shift mul removed lastRemovedDigit roundUp vpDiv vmDiv vrDiv |
	"Step 1: decode the floating point number, and unify normalized and subnormal cases.
	The exponent is decreased by 2 to make room for the interval bounds below."
	ieeeExponent = 0
		ifTrue: [
			e2 := 1 - 1023 - 52 - 2.
			m2 := ieeeMantissa ]
		ifFalse: [
			e2 := ieeeExponent - 1023 - 52 - 2.
			m2 := ieeeMantissa + 16r10000000000000 ].
	acceptBounds := m2 even.

	"Step 2: determine the interval of valid decimal representations [mm, mp] around mv.
	The lower bound is closer when the mantissa is a power of two (except for the smallest normal)."
	mv := m2 * 4.
	mmShift := (ieeeMantissa ~= 0 or: [ ieeeExponent <= 1 ])
		           ifTrue: [ 1 ]
		           ifFalse: [ 0 ].

	"Step 3: convert to a decimal power base, computing vr, vp and vm as the
	128-bit products of mv, mp and mm by a power of 5, shifted right."
	vmIsTrailingZeros := false.
	vrIsTrailingZeros := false.
	e2 >= 0
		ifTrue: [
			q := (e2 * 78913 bitShift: -18) - (e2 > 3 ifTrue: [ 1 ] ifFalse: [ 0 ]).
			e10 := q.
			shift := q - e2 + 125 + (self pow5Bits: q) - 1.
			mul := Pow5InvSplit at: q + 1 ]
		ifFalse: [
			q := (e2 negated * 732923 bitShift: -20) - (e2 < -1 ifTrue: [ 1 ] ifFalse: [ 0 ]).
			e10 := q + e2.
			shift := q - ((self pow5Bits: e2 negated - q) - 125).
			mul := Pow5Split at: e2 negated - q + 1 ].
	vr := self mulShift: mv limbs: mul shift: shift.
	vp := self mulShift: mv + 2 limbs: mul shift: shift.
	vm := self mulShift: mv - 1 - mmShift limbs: mul shift: shift.
	e2 >= 0
		ifTrue: [
			q <= 21 ifTrue: [
				"Only one of mp, mv, and mm can be a multiple of 5, if any."
				mv \\ 5 = 0
					ifTrue: [ vrIsTrailingZeros := (self pow5Factor: mv) >= q ]
					ifFalse: [
						acceptBounds
							ifTrue: [ vmIsTrailingZeros := (self pow5Factor: mv - 1 - mmShift) >= q ]
							ifFalse: [ (self pow5Factor: mv + 2) >= q ifTrue: [ vp := vp - 1 ] ] ] ] ]
		ifFalse: [
			q <= 1
				ifTrue: [
					"mv = 4 * m2 always has at least two trailing 0 bits."
					vrIsTrailingZeros := true.
					acceptBounds
						ifTrue: [ vmIsTrailingZeros := mmShift = 1 ]
						ifFalse: [ vp := vp - 1 ] ]
				ifFalse: [ q < 63 ifTrue: [ vrIsTrailingZeros := (mv bitAnd: (1 bitShift: q) - 1) = 0 ] ] ].

	"Step 4: find the shortest decimal representation in the interval of valid representations."
	removed := 0.
	(vmIsTrailingZeros or: [ vrIsTrailingZeros ])
		ifTrue: [
			"General case, which happens rarely (~0.7%)"
			lastRemovedDigit := 0.
			[ (vpDiv := vp // 10) > (vmDiv := vm // 10) ] whileTrue: [
				vmIsTrailingZeros := vmIsTrailingZeros and: [ vm - (vmDiv * 10) = 0 ].
				vrIsTrailingZeros := vrIsTrailingZeros and: [ lastRemovedDigit = 0 ].
				vrDiv := vr // 10.
				lastRemovedDigit := vr - (vrDiv * 10).
				vr := vrDiv.
				vp := vpDiv.
				vm := vmDiv.
				removed := removed + 1 ].
			vmIsTrailingZeros ifTrue: [
				[ vm - ((vmDiv := vm // 10) * 10) = 0 ] whileTrue: [
					vrIsTrailingZeros := vrIsTrailingZeros and: [ lastRemovedDigit = 0 ].
					vrDiv := vr // 10.
					lastRemovedDigit := vr - (vrDiv * 10).
					vr := vrDiv.
					vp := vp // 10.
					vm := vmDiv.
					removed := removed + 1 ] ].
			(vrIsTrailingZeros and: [ lastRemovedDigit = 5 and: [ vr even ] ])
				ifTrue: [ "Round to even if the exact number is .....50..0" lastRemovedDigit := 4 ].
			"Take vr + 1 if vr is outside bounds or we need to round up."
			digits := ((vr = vm and: [ acceptBounds not or: [ vmIsTrailingZeros not ] ]) or: [ lastRemovedDigit >= 5 ])
				          ifTrue: [ vr + 1 ]
				          ifFalse: [ vr ] ]
		ifFalse: [
			"Specialized for the common case (~99.3%)"
			roundUp := false.
			(vpDiv := vp // 100) > (vmDiv := vm // 100) ifTrue: [
				"Remove two digits at a time (~86.2%)"
				vrDiv := vr // 100.
				roundUp := vr - (vrDiv * 100) >= 50.
				vr := vrDiv.
				vp := vpDiv.
				vm := vmDiv.
				removed := 2 ].
			[ (vpDiv := vp // 10) > (vmDiv := vm // 10) ] whileTrue: [
				vrDiv := vr // 10.
				roundUp := vr - (vrDiv * 10) >= 5.
				vr := vrDiv.
				vp := vpDiv.
				vm := vmDiv.
				removed := removed + 1 ].
			digits := (vr = vm or: [ roundUp ])
				          ifTrue: [ vr + 1 ]
				          ifFalse: [ vr ] ].
	exponent := e10 + removed
]

{ #category : 'private' }
RyuPrinter >> decomposeSmallIntegerMantissa: ieeeMantissa exponent: ieeeExponent [
	"Fast path for integral values in [1, 2^53), d2d_small_int() in d2s.c.
	Answer whether the receiver handled the value."

	| m2 e2 quotient |
	e2 := ieeeExponent - 1023 - 52.
	(e2 > 0 or: [ e2 < -52 ]) ifTrue: [ ^ false ].
	m2 := ieeeMantissa + 16r10000000000000.
	(m2 bitAnd: (1 bitShift: e2 negated) - 1) = 0 ifFalse: [ ^ false ].
	digits := m2 bitShift: e2.
	exponent := 0.
	"Small integers may have trailing decimal zeros"
	[ digits - ((quotient := digits // 10) * 10) = 0 ] whileTrue: [
		digits := quotient.
		exponent := exponent + 1 ].
	^ true
]

{ #category : 'accessing' }
RyuPrinter >> digitString [
	"Answer the decimal digits of the last decomposed Float"

	| string value quotient |
	string := String new: (self decimalLength: digits).
	value := digits.
	string size to: 1 by: -1 do: [ :index |
		quotient := value // 10.
		string at: index put: (Character value: value - (quotient * 10) + 48).
		value := quotient ].
	^ string
]

{ #category : 'accessing' }
RyuPrinter >> digits [
	"Answer the decimal significand of the last decomposed Float"

	^ digits
]

{ #category : 'accessing' }
RyuPrinter >> digits: aDigits exponent: anExponent [
	"Set the decimal value to print with #printDecimalOn:, value = aDigits * (10 raisedTo: anExponent)"

	digits := aDigits.
	exponent := anExponent
]

{ #category : 'accessing' }
RyuPrinter >> exponent [
	"Answer the power of ten of the last decomposed Float"

	^ exponent
]

{ #category : 'private' }
RyuPrinter >> mulShift: m limbs: limbs shift: shift [
	"Answer (m * multiplier) >> shift, where multiplier < 2^140 is given as five 28-bit limbs.
	This replaces the 64x128-bit multiplication of mulShift64() in d2s.c. Splitting m < 2^56 into
	two 28-bit limbs keeps every partial product and column sum within SmallInteger range,
	avoiding LargePositiveInteger arithmetic. Ryu only uses shifts in [118, 125], so the answer
	only depends on limbs 4 to 6 of the product and the carry from the lower limbs."

	| m0 m1 a0 a1 a2 a3 a4 column r4 r5 bits |
	m0 := m bitAnd: 16rFFFFFFF.
	m1 := m bitShift: -28.
	a0 := limbs at: 1.
	a1 := limbs at: 2.
	a2 := limbs at: 3.
	a3 := limbs at: 4.
	a4 := limbs at: 5.
	column := m0 * a0 bitShift: -28.
	column := m0 * a1 + (m1 * a0) + column bitShift: -28.
	column := m0 * a2 + (m1 * a1) + column bitShift: -28.
	column := m0 * a3 + (m1 * a2) + column bitShift: -28.
	column := m0 * a4 + (m1 * a3) + column.
	r4 := column bitAnd: 16rFFFFFFF.
	column := m1 * a4 + (column bitShift: -28).
	r5 := column bitAnd: 16rFFFFFFF.
	bits := shift - 112.
	^ (r4 bitShift: bits negated) + (r5 bitShift: 28 - bits) + ((column bitShift: -28) bitShift: 56 - bits)
]

{ #category : 'private' }
RyuPrinter >> pow5Bits: e [
	"Answer ceil(log2(5^e)), or 1 if e = 0"

	^ (e * 1217359 bitShift: -19) + 1
]

{ #category : 'private' }
RyuPrinter >> pow5Factor: anInteger [
	"Answer the number of times anInteger (> 0) is divisible by 5"

	| count value quotient |
	count := 0.
	value := anInteger.
	[ value - ((quotient := value // 5) * 5) = 0 ] whileTrue: [
		value := quotient.
		count := count + 1 ].
	^ count
]

{ #category : 'printing' }
RyuPrinter >> print: aFloat on: aStream [
	"Print aFloat on aStream using the same format as Float>>#printOn:"

	aFloat isNaN ifTrue: [ ^ aStream nextPutAll: 'Float nan' ].
	aFloat isInfinite ifTrue: [
		aStream nextPutAll: 'Float infinity'.
		^ aFloat > 0 ifFalse: [ aStream nextPutAll: ' negated' ] ].
	aFloat signBit = 1 ifTrue: [ aStream nextPut: $- ].
	aFloat = 0.0 ifTrue: [ ^ aStream nextPutAll: '0.0' ].
	self
		decompose: aFloat;
		printDecimalOn: aStream
]

{ #category : 'printing' }
RyuPrinter >> printDecimalOn: aStream [
	"Print the last decomposed Float with the layout of Float>>#absPrintExactlyOn:base:
	fixed notation when the decimal point lies within 3 places before or 6 places after the first digit,
	scientific notation otherwise."

	| string size pointPosition |
	string := self digitString.
	size := string size.
	pointPosition := size + exponent.
	(pointPosition between: -3 and: 6) ifFalse: [
		aStream nextPut: string first; nextPut: $..
		size = 1
			ifTrue: [ aStream nextPut: $0 ]
			ifFalse: [ aStream next: size - 1 putAll: string startingAt: 2 ].
		aStream nextPut: $e.
		^ pointPosition - 1 printOn: aStream ].
	pointPosition <= 0 ifTrue: [
		aStream nextPutAll: '0.'.
		pointPosition negated timesRepeat: [ aStream nextPut: $0 ].
		^ aStream nextPutAll: string ].
	pointPosition >= size ifTrue: [
		aStream nextPutAll: string.
		pointPosition - size timesRepeat: [ aStream nextPut: $0 ].
		^ aStream nextPutAll: '.0' ].
	aStream
		next: pointPosition putAll: string startingAt: 1;
		nextPut: $.;
		next: size - pointPosition putAll: string startingAt: pointPosition + 1
]

{ #category : 'printing' }
RyuPrinter >> printScientific: aFloat on: aStream [
	"Print aFloat on aStream using the format of d2s() from the Ryu C library"

	| string |
	aFloat isNaN ifTrue: [ ^ aStream nextPutAll: 'NaN' ].
	aFloat signBit = 1 ifTrue: [ aStream nextPut: $- ].
	aFloat isInfinite ifTrue: [ ^ aStream nextPutAll: 'Infinity' ].
	self decompose: aFloat.
	string := self digitString.
	aStream nextPut: string first.
	string size > 1 ifTrue: [
		aStream
			nextPut: $.;
			next: string size - 1 putAll: string startingAt: 2 ].
	aStream nextPut: $E.
	exponent + string size - 1 printOn: aStream
]
