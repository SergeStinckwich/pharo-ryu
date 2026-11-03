"
I run the ShortestFloatPrinterTest tests against DragonboxPrinter, and cross-check it with RyuPrinter.
"
Class {
	#name : 'DragonboxPrinterTest',
	#superclass : 'ShortestFloatPrinterTest',
	#category : 'Ryu-Tests',
	#package : 'Ryu-Tests'
}

{ #category : 'helpers' }
DragonboxPrinterTest >> assertSameAsRyu: aFloat [

	| ryu schubfach |
	ryu := RyuPrinter new decompose: aFloat; yourself.
	schubfach := DragonboxPrinter new decompose: aFloat; yourself.
	self assert: schubfach digits equals: ryu digits.
	self assert: schubfach exponent equals: ryu exponent
]

{ #category : 'accessing' }
DragonboxPrinterTest >> printerClass [

	^ DragonboxPrinter
]

{ #category : 'tests - cross check' }
DragonboxPrinterTest >> testAllExponentsSameAsRyu [
	"Smallest, largest and middle mantissas for every exponent, covering the normal and shorter interval cases"

	0 to: 2046 do: [ :exponent |
		#( 0 1 2 3 16r8000000000000 16rFFFFFFFFFFFFE 16rFFFFFFFFFFFFF ) do: [ :mantissa |
			(exponent = 0 and: [ mantissa = 0 ]) ifFalse: [
				self assertSameAsRyu: (Float fromIEEE64Bit: (exponent bitShift: 52) + mantissa) ] ] ]
]

{ #category : 'tests - integration' }
DragonboxPrinterTest >> testFloatExtensions [

	self assert: 0.1 dragonboxPrintString equals: '0.1'.
	self assert: -2.5 dragonboxPrintString equals: '-2.5'
]

{ #category : 'tests - cross check' }
DragonboxPrinterTest >> testRandomBitPatternsSameAsRyu [

	self
		randomFinitePositiveFloatsDo: [ :float | self assertSameAsRyu: float ]
		count: 100000
		seed: 2020
]

{ #category : 'tests - cross check' }
DragonboxPrinterTest >> testSmallestSubnormals [
	"The smallest subnormals have the widest relative rounding intervals"

	self assert: (DragonboxPrinter scientific: (Float fromIEEE64Bit: 1)) equals: '5E-324'.
	self assert: (DragonboxPrinter scientific: (Float fromIEEE64Bit: 2)) equals: '1E-323'.
	self assert: (DragonboxPrinter scientific: (Float fromIEEE64Bit: 3)) equals: '1.5E-323'
]
