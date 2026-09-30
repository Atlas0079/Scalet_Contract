class_name SCInterface
extends RefCounted


static func ability_text(a) -> String:
	var result := SCAbilityRules.explain(a)
	var v: Dictionary = result.values
	var lines := PackedStringArray(["%s · %s" % [a.actor_name,a.definition.name],
		"移动 %.2f m/s · 力量 %.0f N · 负重 %.1f kg" % [v.move_speed_mps,v.force_n,v.carry_capacity_kg],
		"换弹 ×%.2f · 医疗 ×%.2f · 维修 ×%.2f" % [v.reload_rate,v.treatment_rate,v.repair_rate],
		"瞄准增长 %.2f /秒 · 稳定误差 水平 %.3f° / 垂直 %.3f°" % [v.aim_gain_per_second,v.aim_settled_degrees.x,v.aim_settled_degrees.y],
		"后坐冲量 ×%.2f · 连射支撑 ×%.2f · 视距 %.1f m" % [v.recoil_kick_scale,v.recoil_support_scale,v.view_distance_m],
		"压枪反应 %.2f s · 力度上限 %.0f °/s²" % [v.recoil_response_delay_seconds,v.recoil_control_acceleration],
		"纠正速度 %.1f /s · 后坐预估 %.0f%% · 首次过补偿目标 %.1f°" % [v.recoil_control_frequency,v.recoil_prediction_scale*100,v.recoil_overshoot_degrees]])
	if a.control_mode=="sia": lines.append("SIA：%s · 同步 %.0f%% / 上限 %.0f%%" % [a.pilot.actor_name,v.sync_current*100,v.sync_ceiling*100])
	lines.append("\n有效技能（0–20）")
	for key in result.skills: lines.append("%s：%.2f" % [SCData.catalog.skills.definitions[key].name,result.skills[key]])
	lines.append("\n技能经验持有者")
	for entry in SCSkills.learners(a):
		lines.append("%s · 权重 %.0f%% · %s" % ["自学习芯片" if entry.holder.kind=="chip" else "意识",entry.weight*100,entry.holder.id])
		var xp := PackedStringArray()
		for key in entry.holder.xp: xp.append("%s %.1f" % [SCData.catalog.skills.definitions[key].name,entry.holder.xp[key]])
		lines.append(" / ".join(xp))
	lines.append("\n属性与能力贡献明细（包含失效来源）")
	var origins := {"innate":"天生","structural_part":"部件基础","part_bonus":"部件加成","training":"训练","equipment":"装备","drug":"药效","trait":"特质"}
	for entry in result.explanation.sources:
		lines.append("%s · %s · %s %.3f%s\n  持有者 %s\n  来源 %s" % [origins.get(entry.origin_kind,entry.origin_kind),entry.target_id,entry.operation,entry.value,"" if entry.reason.is_empty() else "（未生效：%s）" % entry.reason,entry.owner_id,entry.source_id])
	return "\n".join(lines)


static func ability_view(a) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.custom_minimum_size = Vector2(600,440)
	text.add_theme_font_size_override("normal_font_size",16)
	text.text = ability_text(a)
	return text
