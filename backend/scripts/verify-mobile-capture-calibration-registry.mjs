#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { validateCalibrationProfileRegistry } from '../src/mobileCaptureCalibration.js';

const inputIndex = process.argv.indexOf('--input');
const inputPath = inputIndex >= 0 ? process.argv[inputIndex + 1] : process.env.MOBILE_CAPTURE_CALIBRATION_REGISTRY_PATH;
if (!inputPath) throw new Error('请通过 --input 或 MOBILE_CAPTURE_CALIBRATION_REGISTRY_PATH 提供已批准的标定配置 JSON');
const registry = JSON.parse(fs.readFileSync(path.resolve(inputPath), 'utf8'));
const result = validateCalibrationProfileRegistry(registry);
process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
if (!result.valid) process.exitCode = 1;
