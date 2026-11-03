Extension { #name : 'Float' }

{ #category : '*Ryu' }
Float >> ryuPrintOn: aStream [
	"Print the shortest decimal representation of the receiver, formatted like #printOn:, using the Ryu algorithm"

	RyuPrinter new print: self on: aStream
]

{ #category : '*Ryu' }
Float >> ryuPrintString [
	"Answer the shortest decimal representation of the receiver, formatted like #printString, using the Ryu algorithm"

	^ RyuPrinter print: self
]

{ #category : '*Ryu' }
Float >> ryuScientificString [
	"Answer the shortest decimal representation of the receiver, formatted like d2s() of the Ryu C library"

	^ RyuPrinter scientific: self
]

{ #category : '*Ryu' }
Float >> schubfachPrintString [
	"Answer the shortest decimal representation of the receiver, formatted like #printString, using the Schubfach algorithm"

	^ SchubfachPrinter print: self
]

{ #category : '*Ryu' }
Float >> dragonboxPrintString [
	"Answer the shortest decimal representation of the receiver, formatted like #printString, using the Dragonbox algorithm"

	^ DragonboxPrinter print: self
]
