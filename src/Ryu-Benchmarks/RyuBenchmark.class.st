"
I compare the speed of RyuPrinter with the default Float>>#printString of Pharo (exact Burger & Dybvig algorithm) and with the inexact print policy.

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
RyuBenchmark >> datasets [
	"Answer label -> floats associations"

	^ {
		  'random bit patterns' -> self randomBitPatterns.
		  'uniform [0, 1)' -> (self collect: [ random next ]).
		  'integral values' -> (self collect: [ (random nextInteger: 1000000) asFloat ]).
		  'two decimals' -> (self collect: [ (random nextInteger: 1000000) / 100.0 ]).
		  'large and tiny' -> (self collect: [ (random next + 1) * (10.0 raisedTo: (random nextInteger: 600) - 300) ]) }
]

{ #category : 'datasets' }
RyuBenchmark >> collect: aBlock [

	^ (1 to: size) collect: [ :i | aBlock value ]
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

	| report |
	random := Random seed: 2018.
	report := String streamContents: [ :stream |
		stream
			nextPutAll: 'Float to string, ns per conversion (best of ';
			print: repetitions;
			nextPutAll: ' runs over ';
			print: size;
			nextPutAll: ' floats)';
			cr.
		stream nextPutAll: ('dataset' padRightTo: 22) , ('printString' padLeftTo: 13) , ('inexact' padLeftTo: 10)
			, ('Ryu' padLeftTo: 8) , ('Ryu E' padLeftTo: 8) , ('speedup' padLeftTo: 9); cr.
		self datasets do: [ :each | self run: each value label: each key on: stream ] ].
	Transcript show: report; cr.
	^ report
]

{ #category : 'running' }
RyuBenchmark >> run: floats label: aString on: aStream [

	| exact inexact ryu scientific |
	exact := self nanosecondsPerFloat: [ :float | float printString ] on: floats.
	inexact := self
		           nanosecondsPerFloat: [ :float |
		           String streamContents: [ :stream | float absPrintInexactlyOn: stream base: 10 ] ]
		           on: (floats collect: [ :float | float abs ]).
	ryu := self nanosecondsPerFloat: [ :float | RyuPrinter print: float ] on: floats.
	scientific := self nanosecondsPerFloat: [ :float | RyuPrinter scientific: float ] on: floats.
	aStream
		nextPutAll: (aString padRightTo: 22);
		nextPutAll: (exact printString padLeftTo: 13);
		nextPutAll: (inexact printString padLeftTo: 10);
		nextPutAll: (ryu printString padLeftTo: 8);
		nextPutAll: (scientific printString padLeftTo: 8);
		nextPutAll: (((exact / ryu) printShowingDecimalPlaces: 1) , 'x' padLeftTo: 9);
		cr
]

{ #category : 'accessing' }
RyuBenchmark >> size: anInteger [

	size := anInteger
]
