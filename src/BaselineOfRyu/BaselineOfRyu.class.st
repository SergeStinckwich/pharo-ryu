Class {
	#name : 'BaselineOfRyu',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfRyu',
	#package : 'BaselineOfRyu'
}

{ #category : 'baselines' }
BaselineOfRyu >> baseline: spec [

	<baseline>
	spec for: #common do: [
		spec
			package: 'Ryu';
			package: 'Ryu-Tests' with: [ spec requires: #( 'Ryu' ) ];
			package: 'Ryu-Benchmarks' with: [ spec requires: #( 'Ryu' ) ].
		spec
			group: 'Core' with: #( 'Ryu' );
			group: 'Tests' with: #( 'Ryu-Tests' );
			group: 'default' with: #( 'Ryu' 'Ryu-Tests' 'Ryu-Benchmarks' ) ]
]
