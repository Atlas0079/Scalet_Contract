extends SceneTree
func _initialize():
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://tests/geometry_reference.json")); var w=SCWorld.new(); var g=w.grid; var failures=0; var checks=0
	for item in data.cells:
		var c=SCData.cell(item[0]); var actual=g.neighbors(c); var expected=[]
		for n in item[2]: expected.append(SCData.cell(n))
		checks+=1
		if g.walkable(c)!=item[1] or actual.size()!=expected.size() or not expected.all(func(n): return n in actual): failures+=1; print("FAIL CELL ",c)
	for item in data.rays:
		var start=Vector2(item[0][0],item[0][1]); var end=Vector2(item[1][0],item[1][1]); var hit=g.raycast(start,end,item[3],item[3],item[2]); checks+=1
		var kind=hit[1].kind if hit[1]!=null else null
		if absf(hit[0]-item[4])>0.00001 or kind!=item[5]: failures+=1; print("FAIL RAY ",item," native ",hit[0]," ",kind)
	for item in data.paths:
		var path=g.find_path(SCData.cell(item[0]),SCData.cell(item[1]),g.zones[item[2]].cells); checks+=1
		if absf(g.path_cost(path)-item[3])>0.00001: failures+=1; print("FAIL PATH ",item)
	checks+=2
	if data.visible.size()!=w.perception.visible_cells.size() or not data.visible.all(func(c): return w.perception.visible_cells.has(SCData.cell(c))): failures+=1; print("FAIL INITIAL VISION")
	if data.doors!=w.perception.doors: failures+=1; print("FAIL INITIAL DOORS")
	print("PYGAME PARITY: ",checks," checks; ",failures," failures"); quit(0 if failures==0 else 1)
