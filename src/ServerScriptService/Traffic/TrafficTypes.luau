--!strict
export type Node = { id: string, position: Vector3, direction: Vector3, road: string,
	speed: number, lane: string, intersection: string?, behavior: string?, outgoing: {string} }
export type Edge = { id: string, from: string, to: string, control1: Vector3,
	control2: Vector3, speed: number, lane: string, road: string,
	intersection: string?, enabled: boolean? }
export type Data = { version: number, approved: boolean, nodes: {Node}, edges: {Edge},
	spawns: {string}, review: {string} }
export type Sample = { position: Vector3, direction: Vector3, distance: number, curvature: number }
export type Path = { edge: Edge, samples: {Sample}, length: number, maxCurvature: number }
export type Network = { nodes: {[string]: Node}, paths: {[string]: Path}, spawns: {string},
	data: Data, outgoing: {[string]: {string}} }
return {}
