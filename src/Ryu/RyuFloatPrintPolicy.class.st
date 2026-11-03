"
I am a Float print policy that prints base 10 Floats with the Ryu algorithm and falls back on exact printing for other bases.

Use me for a dynamic extent:
	FloatPrintPolicy value: RyuFloatPrintPolicy new during: [ 0.1 printString ]
"
Class {
	#name : 'RyuFloatPrintPolicy',
	#superclass : 'Object',
	#category : 'Ryu',
	#package : 'Ryu'
}

{ #category : 'printing' }
RyuFloatPrintPolicy >> absPrint: float on: stream base: base [

	base = 10 ifFalse: [ ^ float absPrintExactlyOn: stream base: base ].
	RyuPrinter new
		decompose: float;
		printDecimalOn: stream
]
