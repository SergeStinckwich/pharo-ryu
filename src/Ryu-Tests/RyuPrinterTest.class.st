"
I test RyuPrinter.

Expected strings in the scientific format come from the test suite of the Ryu C library (d2s_test.cc).
Expected strings in the Pharo format are cross-checked against Float>>#printString, which uses an exact (but slow) shortest printing algorithm.
"
Class {
	#name : 'RyuPrinterTest',
	#superclass : 'TestCase',
	#category : 'Ryu-Tests',
	#package : 'Ryu-Tests'
}

{ #category : 'helpers' }
RyuPrinterTest >> assertRoundTrip: aFloat [

	| string |
	string := RyuPrinter print: aFloat.
	self
		assert: (Number readFrom: string) asIEEE64BitWord
		equals: aFloat asIEEE64BitWord.
	"Pharo reads '5e-324' as 0.0 but '5.0e-324' correctly, so add the missing fraction part"
	string := (RyuPrinter scientific: aFloat) asLowercase.
	(string includes: $.) ifFalse: [ string := string copyReplaceAll: 'e' with: '.0e' ].
	self
		assert: (Number readFrom: string) asIEEE64BitWord
		equals: aFloat asIEEE64BitWord
]

{ #category : 'helpers' }
RyuPrinterTest >> assertSameAsPrintString: aFloat [
	"When the exact value of aFloat lies exactly halfway between two shortest candidates,
	Ryu rounds half to even while Float>>#printString rounds half up: check that this is the only difference."

	| ryu pharo printer exact unit |
	ryu := RyuPrinter print: aFloat.
	pharo := aFloat printString.
	ryu = pharo ifTrue: [ ^ self ].
	printer := RyuPrinter new
		           decompose: aFloat;
		           yourself.
	self assert: printer digits even.
	exact := aFloat abs asTrueFraction.
	unit := 10 raisedTo: printer exponent.
	self assert: exact - (printer digits * unit) equals: unit / 2.
	printer digits: printer digits + 1 exponent: printer exponent.
	self
		assert: (String streamContents: [ :stream |
				 aFloat signBit = 1 ifTrue: [ stream nextPut: $- ].
				 printer printDecimalOn: stream ])
		equals: pharo
]

{ #category : 'helpers' }
RyuPrinterTest >> assertScientific: aString for: aFloat [

	self assert: (RyuPrinter scientific: aFloat) equals: aString
]

{ #category : 'helpers' }
RyuPrinterTest >> floatWithExponent: ieeeExponent mantissa: ieeeMantissa [

	^ Float fromIEEE64Bit: (ieeeExponent bitShift: 52) + ieeeMantissa
]

{ #category : 'helpers' }
RyuPrinterTest >> randomFinitePositiveFloatsDo: aBlock count: anInteger seed: aSeed [
	"Evaluate aBlock with anInteger Floats made of uniformly random bit patterns"

	| random high bits |
	random := Random seed: aSeed.
	[ :exit |
	| count |
	count := 0.
	[
	high := (random nextInteger: 16r80000000) - 1.
	(high bitShift: -20) = 16r7FF ifFalse: [
		bits := (high bitShift: 32) + (random nextInteger: 16r100000000) - 1.
		aBlock value: (Float fromIEEE64Bit: bits).
		count := count + 1.
		count = anInteger ifTrue: [ exit value ] ] ] repeat ] valueWithExit
]

{ #category : 'tests - ryu reference' }
RyuPrinterTest >> testBasic [

	self assertScientific: '0E0' for: 0.0.
	self assertScientific: '-0E0' for: Float negativeZero.
	self assertScientific: '1E0' for: 1.0.
	self assertScientific: '-1E0' for: -1.0.
	self assertScientific: 'NaN' for: Float nan.
	self assertScientific: 'Infinity' for: Float infinity.
	self assertScientific: '-Infinity' for: Float infinity negated
]

{ #category : 'tests - decomposition' }
RyuPrinterTest >> testDecompose [

	| printer |
	printer := RyuPrinter new.
	printer decompose: 0.3.
	self assert: printer digits equals: 3.
	self assert: printer exponent equals: -1.
	printer decompose: -123.456.
	self assert: printer digits equals: 123456.
	self assert: printer exponent equals: -3.
	printer decompose: 1.0e23.
	self assert: printer digits equals: 1.
	self assert: printer exponent equals: 23.
	printer decompose: 1200.0.
	self assert: printer digits equals: 12.
	self assert: printer exponent equals: 2.
	printer decompose: 0.0.
	self assert: printer digits equals: 0.
	self assert: printer exponent equals: 0
]

{ #category : 'tests - decomposition' }
RyuPrinterTest >> testDecomposeRejectsNonFinite [

	self should: [ RyuPrinter new decompose: Float nan ] raise: Error.
	self should: [ RyuPrinter new decompose: Float infinity ] raise: Error
]

{ #category : 'tests - integration' }
RyuPrinterTest >> testFloatExtensions [

	self assert: 0.1 ryuPrintString equals: '0.1'.
	self assert: 0.1 ryuScientificString equals: '1E-1'.
	self assert: (String streamContents: [ :stream | -2.5 ryuPrintOn: stream ]) equals: '-2.5'
]

{ #category : 'tests - pharo format' }
RyuPrinterTest >> testIntegralFloatsMatchPrintString [

	1 to: 100000 do: [ :i | self assertSameAsPrintString: i asFloat ].
	0 to: 62 do: [ :i | self assertSameAsPrintString: (2 raisedTo: i) asFloat ].
	0 to: 22 do: [ :i | self assertSameAsPrintString: (10 raisedTo: i) asFloat ]
]

{ #category : 'tests - ryu reference' }
RyuPrinterTest >> testLooksLikePow5 [
	"These numbers have a mantissa that is a multiple of the largest power of 5 that fits,
	and an exponent that causes the computation for q to result in 22, which is a corner
	case for Ryu."

	self assertScientific: '5.764607523034235E39' for: (Float fromIEEE64Bit: 16r4830F0CF064DD592).
	self assertScientific: '1.152921504606847E40' for: (Float fromIEEE64Bit: 16r4840F0CF064DD592).
	self assertScientific: '2.305843009213694E40' for: (Float fromIEEE64Bit: 16r4850F0CF064DD592)
]

{ #category : 'tests - ryu reference' }
RyuPrinterTest >> testLotsOfTrailingZeros [

	self assertScientific: '2.9802322387695312E-8' for: 2.98023223876953125e-8
]

{ #category : 'tests - ryu reference' }
RyuPrinterTest >> testMinAndMax [

	self assertScientific: '1.7976931348623157E308' for: (Float fromIEEE64Bit: 16r7FEFFFFFFFFFFFFF).
	self assertScientific: '5E-324' for: (Float fromIEEE64Bit: 1)
]

{ #category : 'tests - ryu reference' }
RyuPrinterTest >> testMinMaxShift [
	"The C test ORs a 53-bit all-ones mantissa into the bits, which also increments the exponent:
	ieeeParts2Double(false, 6, maxMantissa) has exponent 7."

	| maxMantissa |
	maxMantissa := (1 bitShift: 52) - 1.
	self assertScientific: '1.7800590868057611E-307' for: (self floatWithExponent: 4 mantissa: 0).
	self assertScientific: '2.8480945388892175E-306' for: (self floatWithExponent: 7 mantissa: maxMantissa).
	self assertScientific: '2.446494580089078E-296' for: (self floatWithExponent: 41 mantissa: 0).
	self assertScientific: '4.8929891601781557E-296' for: (self floatWithExponent: 41 mantissa: maxMantissa).
	self assertScientific: '1.8014398509481984E16' for: (self floatWithExponent: 1077 mantissa: 0).
	self assertScientific: '3.6028797018963964E16' for: (self floatWithExponent: 1077 mantissa: maxMantissa).
	self assertScientific: '2.900835519859558E-216' for: (self floatWithExponent: 307 mantissa: 0).
	self assertScientific: '5.801671039719115E-216' for: (self floatWithExponent: 307 mantissa: maxMantissa).
	self assertScientific: '3.196104012172126E-27' for: (self floatWithExponent: 934 mantissa: 16r000FA7161A4D6E0C)
]

{ #category : 'tests - ryu reference' }
RyuPrinterTest >> testOutputLength [

	self assertScientific: '1E0' for: 1.0.
	self assertScientific: '1.2E0' for: 1.2.
	self assertScientific: '1.23E0' for: 1.23.
	self assertScientific: '1.234E0' for: 1.234.
	self assertScientific: '1.2345E0' for: 1.2345.
	self assertScientific: '1.23456E0' for: 1.23456.
	self assertScientific: '1.234567E0' for: 1.234567.
	self assertScientific: '1.2345678E0' for: 1.2345678.
	self assertScientific: '1.23456789E0' for: 1.23456789.
	self assertScientific: '1.234567895E0' for: 1.234567895.
	self assertScientific: '1.2345678901E0' for: 1.2345678901.
	self assertScientific: '1.23456789012E0' for: 1.23456789012.
	self assertScientific: '1.234567890123E0' for: 1.234567890123.
	self assertScientific: '1.2345678901234E0' for: 1.2345678901234.
	self assertScientific: '1.23456789012345E0' for: 1.23456789012345.
	self assertScientific: '1.234567890123456E0' for: 1.234567890123456.
	self assertScientific: '1.2345678901234567E0' for: 1.2345678901234567.
	"Test 32-bit chunking"
	self assertScientific: '4.294967294E0' for: 4.294967294.
	self assertScientific: '4.294967295E0' for: 4.294967295.
	self assertScientific: '4.294967296E0' for: 4.294967296.
	self assertScientific: '4.294967297E0' for: 4.294967297.
	self assertScientific: '4.294967298E0' for: 4.294967298
]

{ #category : 'tests - pharo format' }
RyuPrinterTest >> testPharoFormat [

	#( 0.1 '0.1' 100.0 '100.0' 123456.0 '123456.0' 1234567.0 '1.234567e6' 0.001 '0.001' 0.0001 '0.0001'
	   1.0e-5 '1.0e-5' 12.5 '12.5' 1.0e23 '1.0e23' 1.5e300 '1.5e300' 5.0e-324 '5.0e-324'
	   1.7976931348623157e308 '1.7976931348623157e308' -0.5 '-0.5' 0.0 '0.0' )
		pairsDo: [ :float :string | self assert: (RyuPrinter print: float) equals: string ].
	self assert: (RyuPrinter print: Float negativeZero) equals: '-0.0'.
	self assert: (RyuPrinter print: Float nan) equals: 'Float nan'.
	self assert: (RyuPrinter print: Float infinity) equals: 'Float infinity'.
	self assert: (RyuPrinter print: Float infinity negated) equals: 'Float infinity negated'
]

{ #category : 'tests - integration' }
RyuPrinterTest >> testPrintPolicy [

	FloatPrintPolicy value: RyuFloatPrintPolicy new during: [
		self assert: 0.1 printString equals: '0.1'.
		self assert: -1.0e-10 printString equals: '-1.0e-10'.
		self assert: (0.5 printStringBase: 2) equals: '0.1' ]
]

{ #category : 'tests - pharo format' }
RyuPrinterTest >> testPowersOfTwo [

	-1074 to: 1023 do: [ :e |
		| float |
		float := (2 raisedTo: e) asFloat.
		self assertSameAsPrintString: float.
		self assertRoundTrip: float ]
]

{ #category : 'tests - pharo format' }
RyuPrinterTest >> testRandomBitPatternsMatchPrintString [

	self
		randomFinitePositiveFloatsDo: [ :float |
			self assertSameAsPrintString: float.
			self assertSameAsPrintString: float negated ]
		count: 20000
		seed: 42
]

{ #category : 'tests - round trip' }
RyuPrinterTest >> testRandomBitPatternsRoundTrip [

	self
		randomFinitePositiveFloatsDo: [ :float | self assertRoundTrip: float ]
		count: 5000
		seed: 4242
]

{ #category : 'tests - pharo format' }
RyuPrinterTest >> testRandomDecimalsMatchPrintString [
	"Short decimals such as prices or measures, where trailing zero removal matters"

	| random |
	random := Random seed: 7.
	10000 timesRepeat: [
		| float |
		float := ((random nextInteger: 10000000) / (10 raisedTo: (random nextInteger: 12))) asFloat.
		self assertSameAsPrintString: float.
		self assertRoundTrip: float ]
]

{ #category : 'tests - ryu reference' }
RyuPrinterTest >> testRegression [

	self assertScientific: '-2.109808898695963E16' for: -2.109808898695963e16.
	self assertScientific: '4.940656E-318' for: 4.940656e-318.
	self assertScientific: '1.18575755E-316' for: 1.18575755e-316.
	self assertScientific: '2.989102097996E-312' for: 2.989102097996e-312.
	self assertScientific: '9.0608011534336E15' for: 9.0608011534336e15.
	self assertScientific: '4.708356024711512E18' for: 4.708356024711512e18.
	self assertScientific: '9.409340012568248E18' for: 9.409340012568248e18.
	self assertScientific: '1.2345678E0' for: 1.2345678
]

{ #category : 'tests - ryu reference' }
RyuPrinterTest >> testSmallIntegers [

	self assertScientific: '9.007199254740991E15' for: 9007199254740991.0.
	self assertScientific: '9.007199254740992E15' for: 9007199254740992.0.
	self assertScientific: '1E0' for: 1.0.
	self assertScientific: '1.2E1' for: 12.0.
	self assertScientific: '1.23E2' for: 123.0.
	self assertScientific: '1.2345678E7' for: 12345678.0.
	self assertScientific: '1.23456789012345E14' for: 123456789012345.0.
	self assertScientific: '1E15' for: 1.0e15.
	self assertScientific: '1E16' for: 1.0e16.
	self assertScientific: '1.000000000001E15' for: 1000000000001000.0
]

{ #category : 'tests - pharo format' }
RyuPrinterTest >> testSubnormals [

	| random |
	random := Random seed: 99.
	1 to: 64 do: [ :mantissa | self assertSameAsPrintString: (Float fromIEEE64Bit: mantissa) ].
	5000 timesRepeat: [
		| float |
		float := Float fromIEEE64Bit: (random nextInteger: (1 bitShift: 52) - 1).
		self assertSameAsPrintString: float.
		self assertRoundTrip: float ]
]

{ #category : 'tests - ryu reference' }
RyuPrinterTest >> testSwitchToSubnormal [

	self assertScientific: '2.2250738585072014E-308' for: 2.2250738585072014e-308
]
