import { DATA } from './content.js';
import * as P from './core/progression.js';
import { SaveRepository } from './platform/storage.js';

export class Game {
  constructor(profile = 'experience', options = {}) {
    this.profile = profile;
    this.repo = new SaveRepository({ ...options, profile });
    this.state = null;
    this.revision = null;
    this.events = [];
    this.listeners = [];
    this.busy = false;
    this.warnings = [];
  }
  onChange(fn) { this.listeners.push(fn); }
  notify() { for (const fn of this.listeners) fn(); }
  event(kind, data = {}, state = this.state) {
    const event = { kind, utc_ms: Date.now(), debug: Boolean(state?.debugSimulated), profile: this.profile, ...data };
    this.events.push(event);
    return event;
  }
  now(state = this.state) { return Date.now() + (state?.debug_offset_ms || 0); }
  async start() {
    await this.repo.open();
    let loaded = await this.repo.load();
    if (!loaded) {
      const state = P.initialState(Date.now(), 12345, this.profile);
      state.logs = [this.event('FIRST_START', {}, state)];
      state.operation_ids = [];
      try { loaded = await this.repo.create(state); }
      catch (error) { if (error.code === 'CONFLICT') loaded = await this.repo.load(); else throw error; }
    } else this.event('RESTART', {}, loaded.state);
    this.state = loaded.state; this.revision = loaded.revision;
    this.warnings = loaded.warnings || [];
    if (loaded.recovered) this.state.logs = [...(this.state.logs || []), this.event('SAVE_RECOVERED', { warnings: this.warnings }, this.state)].slice(-300);
    await this.settle('REAL_TIME').catch(error => {
      if (error.code === 'TIME_ANOMALY') this.timeAnomaly = true;
      else this.startError = error;
    });
    this.notify();
  }
  async refresh() {
    const loaded = await this.repo.load();
    if (!loaded) throw new Error('セーブが見つかりません。初期化せず停止しました。');
    this.state = loaded.state; this.revision = loaded.revision;
    if (loaded.warnings?.length) this.warnings = loaded.warnings;
    return loaded;
  }
  async apply(kind, reducer, data = {}) {
    if (this.pendingOperation) {
      const pending = this.pendingOperation;
      await this.refresh();
      if (this.state.operation_ids?.includes(pending.token)) {
        this.pendingOperation = null; this.notify();
        if (pending.kind === kind) return this.state;
        throw new Error('前の保存完了を確認しました。現在の状態を確認して操作し直してください。');
      }
      this.pendingOperation = null;
    }
    if (this.busy) throw new Error('保存処理中です。完了を待ってください。');
    this.busy = true; this.notify();
    const token = crypto.randomUUID();
    try {
      for (let attempt = 0; attempt < 4; attempt++) {
        const candidate = reducer(structuredClone(this.state));
        const event = this.event(kind, data, candidate);
        candidate.logs = [...(candidate.logs || []), event].slice(-300);
        candidate.operation_ids = [...(candidate.operation_ids || []), token].slice(-64);
        try {
          const loaded = await this.repo.commit(candidate, this.revision);
          this.state = loaded.state; this.revision = loaded.revision;
          this.lastError = null;
          return this.state;
        } catch (error) {
          if (error.code === 'CONFLICT') {
            await this.refresh();
            if (this.state.operation_ids?.includes(token)) return this.state;
            continue;
          }
          if (error.code === 'COMMITTED_UNKNOWN') {
            this.pendingOperation = { token, kind };
            await this.refresh();
            if (this.state.operation_ids?.includes(token)) {
              this.pendingOperation = null;
              this.event('READBACK_RECONCILED', { operation: kind });
              return this.state;
            }
          }
          throw error;
        }
      }
      throw new Error('別画面の保存が競合しました。現在のセーブを読み直して再試行してください。');
    } catch (error) {
      this.lastError = error; this.event('SAVE_OR_OPERATION_FAILED', { operation: kind, code: error.code || 'INVALID_OPERATION' });
      throw error;
    } finally { this.busy = false; this.notify(); }
  }
  async settle(kind = 'REAL_TIME') {
    const request = crypto.randomUUID();
    return this.apply(kind, state => {
      const [next, receipt] = P.settle(state, this.now(state), request);
      if (receipt.status === 'TIME_ANOMALY') {
        const error = new Error('時計がチェックポイントより前です。報酬を付与せずセーブを保全しました。');
        error.code = 'TIME_ANOMALY'; this.timeAnomaly = true; throw error;
      }
      next.last_receipt.source = kind;
      if (receipt.awarded_steps) next.last_reward_receipt = structuredClone(next.last_receipt);
      return next;
    });
  }
  async debugAdvance() {
    const request = crypto.randomUUID();
    return this.apply('DEBUG_8_HOURS', state => {
      state.debug_offset_ms = (state.debug_offset_ms || 0) + 8 * 3600000;
      state.debugSimulated = true;
      const [next, receipt] = P.settle(state, this.now(state), request);
      if (receipt.status !== 'APPLIED') throw new Error('時刻異常を解消してから時間送りを実行してください。');
      next.last_receipt.source = 'DEBUG_8_HOURS';
      next.last_reward_receipt = structuredClone(next.last_receipt);
      return next;
    }, { simulated_ms: 8 * 3600000 });
  }
  async changeRoute(route) {
    const request = crypto.randomUUID();
    return this.apply('ROUTE_CHANGE', state => {
      const [next, receipt] = P.switchRoute(state, this.now(state), route, request);
      if (receipt.status !== 'APPLIED') throw new Error('時計の基準を確認してください。探索先は変更されていません。');
      next.last_receipt.source = 'REAL_TIME';
      return next;
    }, { route });
  }
  async rebaseClock() {
    const state = await this.apply('CLOCK_REBASE', s => P.rebaseClock(s, this.now(s), true));
    this.timeAnomaly = false; return state;
  }
  async finishFight(boss, result, seed, loadout) {
    return this.apply('BOSS_RESULT', state => {
      const next = P.recordFight(state, boss, result, seed);
      next.previous_fight = state.last_fight || null;
      next.last_fight = { boss, result, seed, loadout: [...loadout] };
      return next;
    }, { boss, seed, win: result.win, time_ms: result.time_ms });
  }
  logExport() {
    return { version: 'G1-0.1.0', scope: 'Local only; no personal identifiers', profile: this.profile,
      debugSimulated: Boolean(this.state?.debugSimulated), saved: this.state?.logs || [], session: this.events };
  }
}
