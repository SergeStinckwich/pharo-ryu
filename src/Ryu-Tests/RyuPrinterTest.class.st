"
I run the ShortestFloatPrinterTest tests against RyuPrinter, and test the Ryu integration with Float printing.
"
Class {
	#name : 'RyuPrinterTest',
	#superclass : 'ShortestFloatPrinterTest',
	#category : 'Ryu-Tests',
	#package : 'Ryu-Tests'
}

{ #category : 'accessing' }
RyuPrinterTest >> printerClass [

	^ RyuPrinter
]

{ #category : 'tests - integration' }
RyuPrinterTest >> testFloatExtensions [

	self assert: 0.1 ryuPrintString equals: '0.1'.
	self assert: 0.1 ryuScientificString equals: '1E-1'.
	self assert: (String streamContents: [ :stream | -2.5 ryuPrintOn: stream ]) equals: '-2.5'
]

{ #category : 'tests - integration' }
RyuPrinterTest >> testPrintPolicy [

	FloatPrintPolicy value: RyuFloatPrintPolicy new during: [
		self assert: 0.1 printString equals: '0.1'.
		self assert: -1.0e-10 printString equals: '-1.0e-10'.
		self assert: (0.5 printStringBase: 2) equals: '0.1' ]
]
