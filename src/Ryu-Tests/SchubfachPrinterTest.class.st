"
I run the ShortestFloatPrinterTest tests against SchubfachPrinter, and cross-check it with RyuPrinter.
"
Class {
	#name : 'SchubfachPrinterTest',
	#superclass : 'ShortestFloatPrinterTest',
	#category : 'Ryu-Tests',
	#package : 'Ryu-Tests'
}

{ #category : 'helpers' }
SchubfachPrinterTest >> assertSameAsRyu: aFloat [

	| ryu schubfach |
	ryu := RyuPrinter new decompose: aFloat; yourself.
	schubfach := SchubfachPrinter new decompose: aFloat; yourself.
	self assert: schubfach digits equals: ryu digits.
	self assert: schubfach exponent equals: ryu exponent
]

{ #category : 'accessing' }
SchubfachPrinterTest >> printerClass [

	^ SchubfachPrinter
]

{ #category : 'tests - cross check' }
SchubfachPrinterTest >> testAllExponentsSameAsRyu [
	"Smallest, largest and middle mantissas for every exponent, covering regular and irregular spacing"

	0 to: 2046 do: [ :exponent |
		#( 0 1 2 3 16r8000000000000 16rFFFFFFFFFFFFE 16rFFFFFFFFFFFFF ) do: [ :mantissa |
			(exponent = 0 and: [ mantissa = 0 ]) ifFalse: [
				self assertSameAsRyu: (Float fromIEEE64Bit: (exponent bitShift: 52) + mantissa) ] ] ]
]

{ #category : 'tests - integration' }
SchubfachPrinterTest >> testFloatExtensions [

	self assert: 0.1 schubfachPrintString equals: '0.1'.
	self assert: -2.5 schubfachPrintString equals: '-2.5'
]

{ #category : 'tests - cross check' }
SchubfachPrinterTest >> testRandomBitPatternsSameAsRyu [

	self
		randomFinitePositiveFloatsDo: [ :float | self assertSameAsRyu: float ]
		count: 100000
		seed: 2021
]

{ #category : 'tests - cross check' }
SchubfachPrinterTest >> testSmallestSubnormals [
	"DoubleToDecimal scales subnormals with a mantissa below 3 by 10, giving 4.9E-324 for the first one: check they are shortest here"

	self assert: (SchubfachPrinter scientific: (Float fromIEEE64Bit: 1)) equals: '5E-324'.
	self assert: (SchubfachPrinter scientific: (Float fromIEEE64Bit: 2)) equals: '1E-323'.
	self assert: (SchubfachPrinter scientific: (Float fromIEEE64Bit: 3)) equals: '1.5E-323'
]
