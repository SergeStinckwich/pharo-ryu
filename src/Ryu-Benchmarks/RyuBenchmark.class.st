"
I compare the speed of RyuPrinter and SchubfachPrinter with the default Float>>#printString of Pharo (exact Burger & Dybvig algorithm) and with the inexact print policy.

The first table times complete conversions to a String, the second one only the shortest decimal computation (#decompose:), without the formatting shared by both printers.

	RyuBenchmark run. ""answers a report and shows it on the Transcript""
	RyuBenchmark new size: 5000; repetitions: 3; run.
"
Class {
	#name : 'RyuBenchmark',
	#superclass : 'Object',
	#instVars : [
		'size',
		'repetitions',
		'random'
	],
	#category : 'Ryu-Benchmarks',
	#package : 'Ryu-Benchmarks'
}

{ #category : 'running' }
RyuBenchmark class >> run [

	^ self new run
]

{ #category : 'datasets' }
RyuBenchmark >> collect: aBlock [

	^ (1 to: size) collect: [ :i | aBlock value ]
]

{ #category : 'datasets' }
RyuBenchmark >> datasets [
	"Answer label -> floats associations"

	^ {
		  'random bit patterns' -> self randomBitPatterns.
		  'uniform [0, 1)' -> (self collect: [ random next ]).
		  'integral values' -> (self collect: [ (random nextInteger: 1000000) asFloat ]).
		  'two decimals' -> (self collect: [ (random nextInteger: 1000000) / 100.0 ]).
		  'large and tiny' -> (self collect: [ (random next + 1) * (10.0 raisedTo: (random nextInteger: 600) - 300) ]) }
]

{ #category : 'initialization' }
RyuBenchmark >> initialize [

	super initialize.
	size := 10000.
	repetitions := 5
]

{ #category : 'running' }
RyuBenchmark >> nanosecondsPerFloat: aBlock on: floats [
	"Answer the best time over the repetitions, in nanoseconds per conversion"

	| best start |
	floats do: aBlock. "warm up"
	best := SmallInteger maxVal.
	repetitions timesRepeat: [
		Smalltalk garbageCollectMost.
		start := Time microsecondClockValue.
		floats do: aBlock.
		best := best min: Time microsecondClockValue - start ].
	^ best * 1000 // floats size
]

{ #category : 'printing' }
RyuBenchmark >> print: anInteger on: aStream [

	aStream nextPutAll: (anInteger printString padLeftTo: 12)
]

{ #category : 'printing' }
RyuBenchmark >> printSpeedup: aNumber on: aStream [

	aStream nextPutAll: ((aNumber printShowingDecimalPlaces: 1) , 'x' padLeftTo: 12)
]

{ #category : 'datasets' }
RyuBenchmark >> randomBitPatterns [

	| floats high |
	floats := OrderedCollection new: size.
	[ floats size < size ] whileTrue: [
		high := (random nextInteger: 16r100000000) - 1.
		(high bitShift: -20) \\ 16r800 = 16r7FF ifFalse: [
			floats add: (Float fromIEEE64Bit: (high bitShift: 32) + (random nextInteger: 16r100000000) - 1) ] ].
	^ floats asArray
]

{ #category : 'accessing' }
RyuBenchmark >> repetitions: anInteger [

	repetitions := anInteger
]

{ #category : 'running' }
RyuBenchmark >> run [
	"Answer a report of nanoseconds per conversion for each dataset and printer"

	| datasets report |
	random := Random seed: 2018.
	datasets := self datasets.
	report := String streamContents: [ :stream |
		stream
			nextPutAll: 'Float to string, ns per conversion (best of ';
			print: repetitions;
			nextPutAll: ' runs over ';
			print: size;
			nextPutAll: ' floats)';
			cr.
		stream nextPutAll: ('dataset' padRightTo: 22).
		#( 'printString' 'inexact' 'Ryu' 'Schubfach' 'Ryu x' 'Schubfach x' ) do: [ :each |
			stream nextPutAll: (each padLeftTo: 12) ].
		stream cr.
		datasets do: [ :each | self runPrinting: each value label: each key on: stream ].
		stream
			cr;
			nextPutAll: 'Shortest decimal only (#decompose:), ns per conversion';
			cr;
			nextPutAll: ('dataset' padRightTo: 22).
		#( 'Ryu' 'Schubfach' 'Schubfach x' ) do: [ :each | stream nextPutAll: (each padLeftTo: 12) ].
		stream cr.
		datasets do: [ :each | self runDecomposing: each value label: each key on: stream ] ].
	Transcript show: report; cr.
	^ report
]

{ #category : 'running' }
RyuBenchmark >> runDecomposing: floats label: aString on: aStream [

	| ryuPrinter schubfachPrinter ryu schubfach |
	ryuPrinter := RyuPrinter new.
	schubfachPrinter := SchubfachPrinter new.
	ryu := self nanosecondsPerFloat: [ :float | ryuPrinter decompose: float ] on: floats.
	schubfach := self nanosecondsPerFloat: [ :float | schubfachPrinter decompose: float ] on: floats.
	aStream nextPutAll: (aString padRightTo: 22).
	self print: ryu on: aStream.
	self print: schubfach on: aStream.
	self printSpeedup: ryu / schubfach on: aStream.
	aStream cr
]

{ #category : 'running' }
RyuBenchmark >> runPrinting: floats label: aString on: aStream [

	| exact inexact ryu schubfach |
	exact := self nanosecondsPerFloat: [ :float | float printString ] on: floats.
	inexact := self
		           nanosecondsPerFloat: [ :float |
		           String streamContents: [ :stream | float absPrintInexactlyOn: stream base: 10 ] ]
		           on: (floats collect: [ :float | float abs ]).
	ryu := self nanosecondsPerFloat: [ :float | RyuPrinter print: float ] on: floats.
	schubfach := self nanosecondsPerFloat: [ :float | SchubfachPrinter print: float ] on: floats.
	aStream nextPutAll: (aString padRightTo: 22).
	self print: exact on: aStream.
	self print: inexact on: aStream.
	self print: ryu on: aStream.
	self print: schubfach on: aStream.
	self printSpeedup: exact / ryu on: aStream.
	self printSpeedup: exact / schubfach on: aStream.
	aStream cr
]

{ #category : 'accessing' }
RyuBenchmark >> size: anInteger [

	size := anInteger
]
