import { useSyncExternalStore } from 'react';
import { Rng } from '../core/rng';
import type { SupplyId } from '../core/types';
import { Battle } from '../battle/battle';
import { runPlayerAuto } from '../battle/ai';
import { buildBattle, rollEncounter } from '../battle/setup';
import { soldierToUnit } from '../meta/soldier';
import {
  applyBattle,
  battleArmy,
  dismissPending,
  march,
  canMarch,
  returnHome,
  prepareNight,
  startExpedition,
  survivalBonus,
  type ExpeditionReport,
} from '../campaign/expedition';
import { autoBattle, autoExpedition, autoPrepare } from '../campaign/autoplay';
import { migrateSave, newGame, SAVE_VERSION, type GameState } from '../meta/game';
import { BaseScene } from '../render/baseScene';
import { BattleScene } from '../render/battleScene';
import { CampaignScene } from '../render/campaignScene';
import type { Engine } from '../render/engine';
import { sfx } from '../audio/sfx';
import { manualSeen, markManualSeen } from './screens/Manual';

export type Screen = 'loading' | 'title' | 'base' | 'prep' | 'campaign' | 'battle' | 'report';

const SAVE_KEY = 'meridius.save.v1';

class AppStore {
  engine!: Engine;
  game: GameState | null = null;
  screen: Screen = 'loading';
  panel: string | null = null;
  soldier: string | null = null;
  baseScene: BaseScene | null = null;
  campaignScene: CampaignScene | null = null;
  battleScene: BattleScene | null = null;
  battleInfo: { title: string; objective: boolean } | null = null;
  report: ExpeditionReport | null = null;
  loadProgress = 0;
  manual: string | null = null;
  version = 0;
  private listeners = new Set<() => void>();

  subscribe = (fn: () => void) => {
    this.listeners.add(fn);
    return () => {
      this.listeners.delete(fn);
    };
  };

  emit() {
    this.version++;
    for (const l of this.listeners) l();
  }

  /** Persist and refresh after any change to the game state. */
  commit() {
    this.save();
    this.emit();
  }

  hasSave(): boolean {
    try {
      return !!localStorage.getItem(SAVE_KEY);
    } catch {
      return false;
    }
  }

  save() {
    if (!this.game) return;
    try {
      localStorage.setItem(SAVE_KEY, JSON.stringify(this.game));
    } catch {
      /* storage unavailable */
    }
  }

  load(): boolean {
    try {
      const raw = localStorage.getItem(SAVE_KEY);
      if (!raw) return false;
      const g = JSON.parse(raw) as GameState;
      if (g.version !== SAVE_VERSION) return false;
      // Saves from before squads keep their soldiers: each becomes a full squad.
      this.game = migrateSave(g);
      return true;
    } catch {
      return false;
    }
  }

  // ---------------------------------------------------------------- flow

  newGame(seed?: number) {
    this.game = newGame(seed);
    this.save();
    this.goBase();
  }

  continueGame() {
    if (!this.load()) return;
    if (this.game!.expedition) this.goCampaign();
    else this.goBase();
  }

  goTitle() {
    this.screen = 'title';
    this.panel = null;
    this.setBaseScene(true);
    this.emit();
  }

  private setBaseScene(dim = false) {
    if (!this.baseScene) {
      this.baseScene = new BaseScene(() => this.game, (id) => this.openPanel(id));
    } else if (this.game) this.baseScene.spawnWalkers(this.game);
    this.baseScene.dim = dim;
    this.engine.onDrag = (dx, dy) => {
      const c = this.baseScene!.cam;
      c.tx -= dx / c.zoom;
      c.ty -= dy / c.zoom;
      c.x = c.tx;
      c.y = c.ty;
    };
    this.engine.setScene(this.baseScene);
    this.campaignScene = null;
    this.battleScene = null;
  }

  goBase() {
    this.screen = 'base';
    this.panel = null;
    this.setBaseScene(false);
    this.emit();
  }

  openPanel(id: string | null) {
    this.panel = id;
    sfx(id ? 'page' : 'click');
    if (this.baseScene) this.baseScene.dim = !!id && this.screen === 'base' && id !== null;
    this.emit();
  }

  openManual(page: string | null) {
    this.manual = page;
    if (page) sfx('page');
    else markManualSeen();
    this.emit();
  }

  openSoldier(id: string | null) {
    this.soldier = id;
    if (id) sfx('page');
    this.emit();
  }

  goPrep() {
    this.screen = 'prep';
    this.panel = null;
    if (this.baseScene) this.baseScene.dim = true;
    sfx('page');
    this.emit();
  }

  launch(campaignId: string, army: string[], supplies: Record<SupplyId, number>, cost: number) {
    if (!this.game) return;
    startExpedition(this.game, campaignId, army, supplies, cost);
    this.save();
    sfx('horn');
    this.goCampaign();
  }

  goCampaign() {
    const g = this.game!;
    const ex = g.expedition!;
    this.screen = 'campaign';
    this.baseScene = null;
    this.campaignScene = new CampaignScene(ex, () => this.game?.expedition ?? null, (id) => this.clickNode(id));
    this.engine.onDrag = (dx, dy) => {
      const c = this.campaignScene!.cam;
      c.tx -= dx / c.zoom;
      c.ty -= dy / c.zoom;
      c.x = c.tx;
      c.y = c.ty;
    };
    this.engine.setScene(this.campaignScene);
    this.battleScene = null;
    this.campaignScene.subscribe(() => this.emit());
    this.emit();
  }

  clickNode(id: string) {
    if (!this.game || !canMarch(this.game, id)) {
      sfx('deny');
      return;
    }
    march(this.game, id);
    this.commit();
  }

  dismiss() {
    if (!this.game) return;
    const wasDefeat = this.game.expedition?.pending?.kind === 'battleResult' && this.game.expedition.pending.report.result === 'defeat';
    dismissPending(this.game);
    if (wasDefeat || !this.game.expedition) {
      this.report = this.game.lastReport;
      this.screen = 'report';
      this.setBaseScene(true);
    }
    this.commit();
  }

  goHome(outcome: 'success' | 'retreat') {
    if (!this.game?.expedition) return;
    this.report = returnHome(this.game, outcome);
    this.screen = 'report';
    this.setBaseScene(true);
    sfx(outcome === 'success' ? 'victory' : 'page');
    this.commit();
  }

  startBattle() {
    const g = this.game;
    const p = g?.expedition?.pending;
    if (!g || !p || p.kind !== 'battle') return;
    const night = prepareNight(g);
    const setup = buildBattle(p.roll, battleArmy(g), { survivalBonus: survivalBonus(g), title: p.title, darkness: night.darkness });
    const battle = new Battle(setup);
    this.battleInfo = { title: p.title, objective: p.objective };
    this.battleScene = new BattleScene(battle);
    if (night.night) this.battleScene.atmo.night = true;
    this.battleScene.onEnd = () => this.finishBattle();
    this.battleScene.subscribe(() => this.emit());
    this.engine.onDrag = (dx, dy) => {
      const c = this.battleScene!.cam;
      c.tx -= dx / c.zoom;
      c.ty -= dy / c.zoom;
      c.x = c.tx;
      c.y = c.ty;
    };
    this.engine.setScene(this.battleScene);
    this.screen = 'battle';
    if (!manualSeen()) this.manual = 'battle';
    this.emit();
  }

  finishBattle() {
    const g = this.game;
    const scene = this.battleScene;
    if (!g || !scene || !this.battleInfo) return;
    applyBattle(g, scene.b, this.battleInfo.title, this.battleInfo.objective);
    this.battleInfo = null;
    this.save();
    this.goCampaign();
  }

  // ---------------------------------------------------------------- automation (play-tests)

  debug = {
    /** Start a stand-alone battle for review, outside any expedition. */
    testBattle: (encounterId: string, opts: { seed?: number; night?: boolean; darkness?: boolean; mapId?: string } = {}) => {
      const g = this.game;
      if (!g) return;
      const roll = rollEncounter(encounterId, new Rng(opts.seed ?? 7), 2);
      if (opts.mapId) roll.mapId = opts.mapId;
      const army = g.roster.slice(0, 6).map((so) => soldierToUnit(so));
      const battle = new Battle(buildBattle(roll, army, { survivalBonus: 0, darkness: opts.darkness }));
      this.battleInfo = null;
      this.battleScene = new BattleScene(battle);
      if (opts.night) this.battleScene.atmo.night = true;
      this.battleScene.onEnd = () => this.goBase();
      this.battleScene.subscribe(() => this.emit());
      this.engine.onDrag = (dx, dy) => {
        const c = this.battleScene!.cam;
        c.tx -= dx / c.zoom;
        c.ty -= dy / c.zoom;
        c.x = c.tx;
        c.y = c.ty;
      };
      this.engine.setScene(this.battleScene);
      this.screen = 'battle';
      this.emit();
    },
    /** Let the AI play the company's current turn (play-test captures). */
    playerTurn: () => {
      const s = this.battleScene;
      if (!s || s.b.phase !== 'player') return;
      runPlayerAuto(s.b);
      s.pump();
    },
    /** Fight the current battle with the AI on both sides. */
    autoBattle: () => {
      const s = this.battleScene;
      if (!s) return;
      const b = s.b;
      if (b.phase === 'deploy') s.begin();
      autoBattle(b);
      s.pump();
    },
    autoExpedition: (seed = 1) => {
      if (!this.game) return;
      autoExpedition(this.game, new Rng(seed));
      this.report = this.game.lastReport;
      this.screen = 'report';
      this.setBaseScene(true);
      this.commit();
    },
    autoPrepare: (seed = 1) => {
      if (!this.game) return false;
      const ok = autoPrepare(this.game, new Rng(seed));
      if (ok) {
        this.save();
        this.goCampaign();
      }
      return ok;
    },
  };
}

export const store = new AppStore();

export function useStore(): AppStore {
  useSyncExternalStore(store.subscribe, () => store.version);
  return store;
}
