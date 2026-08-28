-- A protocol is the immutable operational definition of one complete lane.
-- Tasks and sessions retain snapshots so later rule edits never rewrite history.
CREATE TABLE IF NOT EXISTS assessment_protocols (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
  protocol_code TEXT NOT NULL,
  name TEXT NOT NULL,
  version TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','archived')),
  effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_assessment_protocol_scope_version
  ON assessment_protocols(COALESCE(school_id,''),protocol_code,version);
CREATE INDEX IF NOT EXISTS idx_assessment_protocols_lookup
  ON assessment_protocols(school_id,status,effective_date DESC);

CREATE TABLE IF NOT EXISTS assessment_protocol_items (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  protocol_id TEXT NOT NULL REFERENCES assessment_protocols(id) ON DELETE CASCADE,
  item_code TEXT NOT NULL,
  item_name TEXT NOT NULL,
  sequence_no INTEGER NOT NULL CHECK (sequence_no > 0),
  required BOOLEAN NOT NULL DEFAULT TRUE,
  sensor_profile_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  rule_config_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(protocol_id,item_code),
  UNIQUE(protocol_id,sequence_no)
);

INSERT INTO assessment_protocols(id,school_id,protocol_code,name,version,description,status,effective_date)
VALUES('protocol-global-seven-actions-v1',NULL,'seven-action-complete-lane','向上少年七项完整通道','1.0.0','一名学生一次签到、按固定顺序完成全部项目、一次提交。','active','2026-01-01')
ON CONFLICT(id) DO NOTHING;

INSERT INTO assessment_protocol_items(protocol_id,item_code,item_name,sequence_no,required,sensor_profile_json)
VALUES
  ('protocol-global-seven-actions-v1','连续双脚障碍跳','连续双脚障碍跳',1,TRUE,'{"preferredSensors":["hikvision-high-speed","orbbec-femto-mega"],"recognitionFocus":["起跳","落地","越障","缓冲","触碰","停顿"]}'),
  ('protocol-global-seven-actions-v1','侧向滑步','侧向滑步',2,TRUE,'{"preferredSensors":["hikvision-high-speed","orbbec-femto-mega"],"recognitionFocus":["身体朝向","脚步交叉","膝角","重心高度","移动距离"]}'),
  ('protocol-global-seven-actions-v1','倒退平衡','倒退平衡',3,TRUE,'{"preferredSensors":["hikvision-high-speed","orbbec-femto-mega"],"recognitionFocus":["有效倒退步","横杆边界","触地","扶物","停顿"]}'),
  ('protocol-global-seven-actions-v1','接球-上手掷准','接球-上手掷准',4,TRUE,'{"preferredSensors":["hikvision-high-speed","orbbec-femto-mega"],"recognitionFocus":["接球","屈肘缓冲","衔接","上手投掷","越线","命中"]}'),
  ('protocol-global-seven-actions-v1','手运球绕杆','手运球绕杆',5,TRUE,'{"preferredSensors":["hikvision-high-speed","orbbec-femto-mega"],"recognitionFocus":["手触球","球触地","反弹","绕杆","抱球","漏杆","失控"]}'),
  ('protocol-global-seven-actions-v1','脚运球变向','脚运球变向',6,TRUE,'{"preferredSensors":["hikvision-high-speed","orbbec-femto-mega"],"recognitionFocus":["脚触球","球速和方向变化","球距","绕杆","手触球","停顿"]}'),
  ('protocol-global-seven-actions-v1','定点踢准','定点踢准',7,TRUE,'{"preferredSensors":["hikvision-high-speed","orbbec-femto-mega"],"recognitionFocus":["支撑脚","踢球腿摆动","触球","身体控制","目标命中"]}')
ON CONFLICT(protocol_id,item_code) DO NOTHING;

ALTER TABLE assessment_tasks ADD COLUMN IF NOT EXISTS protocol_id TEXT REFERENCES assessment_protocols(id) ON DELETE SET NULL;
ALTER TABLE assessment_tasks ADD COLUMN IF NOT EXISTS protocol_version TEXT;
ALTER TABLE assessment_tasks ADD COLUMN IF NOT EXISTS protocol_snapshot_json JSONB;

UPDATE assessment_tasks task SET
  protocol_id=COALESCE(task.protocol_id,'protocol-global-seven-actions-v1'),
  protocol_version=COALESCE(task.protocol_version,'1.0.0'),
  protocol_snapshot_json=COALESCE(task.protocol_snapshot_json,jsonb_build_object(
    'id','protocol-global-seven-actions-v1','code','seven-action-complete-lane','name','向上少年七项完整通道','version','1.0.0',
    'description','一名学生一次签到、按固定顺序完成全部项目、一次提交。',
    'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',item.item_code,'name',item.item_name,'sequenceNo',item.sequence_no,'required',item.required,'sensorProfile',item.sensor_profile_json,'ruleConfig',item.rule_config_json) ORDER BY item.sequence_no)
      FROM assessment_protocol_items item WHERE item.protocol_id='protocol-global-seven-actions-v1' AND item.item_code IN (SELECT jsonb_array_elements_text(task.items))),'[]'::jsonb)
  ));

ALTER TABLE test_sessions ADD COLUMN IF NOT EXISTS protocol_id TEXT REFERENCES assessment_protocols(id) ON DELETE SET NULL;
ALTER TABLE test_sessions ADD COLUMN IF NOT EXISTS protocol_version TEXT;
ALTER TABLE test_sessions ADD COLUMN IF NOT EXISTS protocol_snapshot_json JSONB;

UPDATE test_sessions session SET
  protocol_id=COALESCE(session.protocol_id,task.protocol_id),
  protocol_version=COALESCE(session.protocol_version,task.protocol_version),
  protocol_snapshot_json=COALESCE(session.protocol_snapshot_json,task.protocol_snapshot_json)
FROM assessment_tasks task WHERE task.id=session.task_id;

CREATE TABLE IF NOT EXISTS test_session_items (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  session_id TEXT NOT NULL REFERENCES test_sessions(id) ON DELETE CASCADE,
  item_code TEXT NOT NULL,
  item_name TEXT NOT NULL,
  sequence_no INTEGER NOT NULL CHECK (sequence_no > 0),
  required BOOLEAN NOT NULL DEFAULT TRUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','running','completed','needs_review','retest','skipped')),
  attempt_no INTEGER NOT NULL DEFAULT 1 CHECK (attempt_no > 0),
  score NUMERIC(5,2) CHECK (score IS NULL OR (score >= 0 AND score <= 5)),
  confidence NUMERIC(5,4) CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  capture_summary_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(session_id,item_code),
  UNIQUE(session_id,sequence_no)
);
CREATE INDEX IF NOT EXISTS idx_test_session_items_progress ON test_session_items(session_id,sequence_no,status);

INSERT INTO test_session_items(session_id,item_code,item_name,sequence_no,required,status,attempt_no,score,confidence,started_at,completed_at)
SELECT session.id,item->>'code',COALESCE(item->>'name',item->>'code'),(item->>'sequenceNo')::integer,COALESCE((item->>'required')::boolean,TRUE),
  CASE WHEN session.status='needs_review' THEN 'needs_review' WHEN session.status='completed' THEN 'completed' WHEN session.status='retest' THEN 'retest' WHEN session.status='testing' THEN 'pending' ELSE 'pending' END,
  session.attempt_no,score.score,score.confidence,session.started_at,CASE WHEN session.status IN ('completed','needs_review','retest') THEN session.ended_at ELSE NULL END
FROM test_sessions session
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(session.protocol_snapshot_json->'items','[]'::jsonb)) item
LEFT JOIN assessment_scores score ON score.session_id=session.id AND score.item_code=item->>'code'
ON CONFLICT(session_id,item_code) DO NOTHING;
