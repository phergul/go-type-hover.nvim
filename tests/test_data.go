package main

// SimpleStruct is a basic struct
type SimpleStruct struct {
	Field int
}

type (
	// GroupedStruct is inside a type block
	GroupedStruct struct {
		Name string
	}
)

// NestedStruct has anonymous fields
type NestedStruct struct {
	SimpleStruct
	Other struct {
		Val float64
	}
}

type MyInt int

// Interface definition
type Doer interface {
	Do() error
}
