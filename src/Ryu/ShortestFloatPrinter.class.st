"
I am the abstract superclass of printers that convert IEEE 754 double precision Floats to their shortest decimal representation: the shortest digit string that reads back to exactly the same Float, and when several such strings exist, the one closest to the exact binary value, with ties rounded half to even.

My subclasses implement the algorithm in #decomposeMantissa:exponent:, I decode Floats and format the result.

Float>>#printString rounds ties half up, so both differ in the last digit for a few values, e.g. 2.98023223876953125e-8: '2.9802322387695312e-8' here, '2.9802322387695313e-8' for printString. Both are shortest and read back to the same Float.

Two output formats are provided:
- Pharo format, identical to Float>>#printString (e.g. '0.1', '100.0', '1.0e23', 'Float nan')
- Ryu scientific format, identical to d2s() from the Ryu C library (e.g. '1E-1', '1E2', '1E23', 'NaN')

Examples:
	RyuPrinter print: 0.1.                ""'0.1'""
	SchubfachPrinter scientific: 1.0e23.  ""'1E23'""

	(RyuPrinter new decompose: 123.456; yourself) digits. ""123456""

Instance Variables
	digits:	<Integer> decimal significand of the last decomposed Float
	exponent:	<Integer> power of ten of the last decomposed Float, value = digits * (10 raisedTo: exponent)
"
Class {
	#name : 'ShortestFloatPrinter',
	#superclass : 'Object',
	#instVars : [
		'digits',
		'exponent'
	],
	#category : 'Ryu',
	#package : 'Ryu'
}

{ #category : 'testing' }
ShortestFloatPrinter class >> isAbstract [

	^ self == ShortestFloatPrinter
]

{ #category : 'class initialization' }
ShortestFloatPrinter class >> limbsOf: anInteger [
	"Answer the five 28-bit limbs of anInteger < 2^140, least significant first"

	^ (0 to: 4) collect: [ :i | (anInteger bitShift: i * -28) bitAnd: 16rFFFFFFF ]
]

{ #category : 'printing' }
ShortestFloatPrinter class >> print: aFloat [
	"Answer the shortest decimal representation of aFloat, formatted like Float>>#printString"

	^ String new: 24 streamContents: [ :stream | self new print: aFloat on: stream ]
]

{ #category : 'printing' }
ShortestFloatPrinter class >> print: aFloat on: aStream [

	self new print: aFloat on: aStream
]

{ #category : 'printing' }
ShortestFloatPrinter class >> scientific: aFloat [
	"Answer the shortest decimal representation of aFloat, formatted like d2s() of the Ryu C library"

	^ String new: 24 streamContents: [ :stream | self new printScientific: aFloat on: stream ]
]

{ #category : 'private' }
ShortestFloatPrinter >> decimalLength: anInteger [

	| length power |
	length := 1.
	power := 10.
	[ anInteger >= power ] whileTrue: [
		length := length + 1.
		power := power * 10 ].
	^ length
]

{ #category : 'converting' }
ShortestFloatPrinter >> decompose: aFloat [
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
ShortestFloatPrinter >> decomposeMantissa: ieeeMantissa exponent: ieeeExponent [
	"Set digits and exponent to the shortest decimal representation of the positive finite non zero Float
	with the given biased exponent and mantissa bits"

	self subclassResponsibility
]

{ #category : 'private' }
ShortestFloatPrinter >> decomposeSmallIntegerMantissa: ieeeMantissa exponent: ieeeExponent [
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
ShortestFloatPrinter >> digitString [
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
ShortestFloatPrinter >> digits [
	"Answer the decimal significand of the last decomposed Float"

	^ digits
]

{ #category : 'accessing' }
ShortestFloatPrinter >> digits: aDigits exponent: anExponent [
	"Set the decimal value to print with #printDecimalOn:, value = aDigits * (10 raisedTo: anExponent)"

	digits := aDigits.
	exponent := anExponent
]

{ #category : 'accessing' }
ShortestFloatPrinter >> exponent [
	"Answer the power of ten of the last decomposed Float"

	^ exponent
]

{ #category : 'printing' }
ShortestFloatPrinter >> print: aFloat on: aStream [
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
ShortestFloatPrinter >> printDecimalOn: aStream [
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

{ #category : 'private' }
ShortestFloatPrinter >> removeTrailingZeros [
	"Remove the trailing decimal zeros of digits, which is not zero and has at most 17 digits"

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

{ #category : 'printing' }
ShortestFloatPrinter >> printScientific: aFloat on: aStream [
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
