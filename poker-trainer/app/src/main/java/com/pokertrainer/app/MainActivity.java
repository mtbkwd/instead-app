package com.pokertrainer.app;

import android.app.*;
import android.os.*;
import android.graphics.*;
import android.graphics.drawable.*;
import android.view.*;
import android.widget.*;
import java.util.*;

public class MainActivity extends Activity {
  TrainerView trainer;
  @Override public void onCreate(Bundle b){ super.onCreate(b); trainer=new TrainerView(); setContentView(trainer); }

  class TrainerView extends LinearLayout {
    Random rng=new Random(); TextView title,stats,position,pot,board,hero,history,feedback; Button fold,call,raise,next;
    int hands=0, score=0, decisions=0, street=0, potBb=1; String pos="BTN"; String[] positions={"UTG","HJ","CO","BTN","SB","BB"};
    String heroHand="A♠ K♠"; ArrayList<String> deck=new ArrayList<>(), boardCards=new ArrayList<>(); boolean active=true;

    TrainerView(){ super(MainActivity.this); setOrientation(VERTICAL); setPadding(24,20,24,20); setBackgroundColor(Color.rgb(16,20,24));
      title=t("POKER TRAINER",24,true); addView(title); stats=t("Score 0   Decisions 0   Accuracy 0%",14,false); addView(stats);
      addSpacer(10); position=t("",16,true); addView(position); pot=t("",16,false); addView(pot);
      addSpacer(14); board=t("",26,true); board.setGravity(Gravity.CENTER); board.setPadding(12,22,12,22); board.setBackground(round(0xff1d252b,18)); addView(board,new LinearLayout.LayoutParams(-1,-2));
      addSpacer(14); hero=t("",34,true); hero.setGravity(Gravity.CENTER); addView(hero);
      history=t("",14,false); history.setPadding(0,12,0,8); addView(history);
      feedback=t("Choose the best action.",15,true); feedback.setPadding(0,8,0,14); addView(feedback);
      LinearLayout row=new LinearLayout(MainActivity.this); row.setOrientation(HORIZONTAL);
      fold=b("FOLD"); call=b("CALL"); raise=b("RAISE"); row.addView(fold,w()); row.addView(call,w()); row.addView(raise,w()); addView(row);
      next=b("NEXT HAND"); next.setVisibility(GONE); addView(next,new LinearLayout.LayoutParams(-1,dp(52)));
      fold.setOnClickListener(v->choose("Fold")); call.setOnClickListener(v->choose("Call")); raise.setOnClickListener(v->choose("Raise")); next.setOnClickListener(v->newHand());
      newHand();
    }
    TextView t(String s,int sp,boolean bold){ TextView v=new TextView(MainActivity.this); v.setText(s); v.setTextColor(Color.WHITE); v.setTextSize(sp); if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD); return v; }
    Button b(String s){ Button x=new Button(MainActivity.this); x.setText(s); x.setTextSize(15); x.setTextColor(Color.WHITE); x.setBackground(round(0xff29343b,14)); return x; }
    LinearLayout.LayoutParams w(){ LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,dp(54),1); p.setMargins(4,0,4,0); return p; }
    GradientDrawable round(int c,int r){ GradientDrawable g=new GradientDrawable(); g.setColor(c); g.setCornerRadius(dp(r)); return g; }
    int dp(int x){ return (int)(x*getResources().getDisplayMetrics().density+.5f); } void addSpacer(int h){ Space s=new Space(MainActivity.this); addView(s,new LinearLayout.LayoutParams(1,dp(h))); }

    void makeDeck(){ deck.clear(); String[] rs={"2","3","4","5","6","7","8","9","T","J","Q","K","A"}; String[] ss={"♠","♥","♦","♣"}; for(String r:rs)for(String s:ss)deck.add(r+s); Collections.shuffle(deck); }
    void newHand(){ hands++; active=true; street=0; potBb=1; boardCards.clear(); makeDeck();
      pos=positions[rng.nextInt(positions.length)]; heroHand=deck.remove(0)+"  "+deck.remove(0); position.setText("6-max • 100 BB • Hero: "+pos); pot.setText("Pot: 1.5 BB"); board.setText("PRE-FLOP"); hero.setText(heroHand); history.setText(botAction()); feedback.setText("Choose the best action."); feedback.setTextColor(Color.WHITE); showActions(true); updateStats(); }
    String botAction(){ if(pos.equals("UTG")) return "Action folds to you."; String[] a={"Action folds to you.","One player opens to 2.5 BB.","One limper enters the pot."}; return a[rng.nextInt(a.length)]; }
    void choose(String action){ if(!active)return; String best=bestAction(); decisions++; boolean ok=action.equals(best); if(ok)score++; feedback.setText((ok?"✓ Good decision. ":"✕ Better line: ")+best+". "+reason(best)); feedback.setTextColor(ok?0xff76e09a:0xffff9a9a);
      if(action.equals("Fold")){ endHand(); updateStats(); return; }
      if(street<3){ advanceStreet(); } else endHand(); updateStats(); }
    String bestAction(){ int strength=preflopStrength(heroHand); if(street==0){ if(strength>=7)return "Raise"; if(strength>=4)return rng.nextBoolean()?"Call":"Raise"; return "Fold"; }
      int made=postStrength(); if(made>=7)return "Raise"; if(made>=4)return "Call"; return rng.nextInt(4)==0?"Raise":"Fold"; }
    String reason(String best){ if(street==0) return best.equals("Raise")?"This holding is strong enough to enter aggressively from this position.":best.equals("Call")?"The hand has enough equity to continue without inflating the pot.":"The hand is below the profitable continue range."; return best.equals("Raise")?"Your range has enough value or pressure to bet.":best.equals("Call")?"Continuing preserves equity at a reasonable price.":"Your current hand lacks enough equity to continue profitably."; }
    int preflopStrength(String h){ String x=h.replace(" ",""); int s=0; if(x.contains("A"))s+=4; if(x.contains("K"))s+=3; if(x.contains("Q"))s+=2; if(x.contains("J"))s+=1; String[] p=h.trim().split("  "); if(p.length==2){ if(p[0].charAt(1)==p[1].charAt(1))s+=1; if(p[0].charAt(0)==p[1].charAt(0))s+=4; } return s; }
    int postStrength(){ String all=heroHand+" "+String.join(" ",boardCards); Map<Character,Integer> m=new HashMap<>(); for(String c:all.split(" ")) if(c.length()>0)m.put(c.charAt(0),m.getOrDefault(c.charAt(0),0)+1); int max=0,pairs=0; for(int v:m.values()){max=Math.max(max,v); if(v>=2)pairs++;} if(max>=3)return 8; if(pairs>=2)return 7; if(pairs==1)return 5; return preflopStrength(heroHand)/2; }
    void advanceStreet(){ street++; int n=street==1?3:1; for(int i=0;i<n;i++)boardCards.add(deck.remove(0)); String name=street==1?"FLOP":street==2?"TURN":"RIVER"; board.setText(name+"\n"+String.join("   ",boardCards)); potBb+=2+rng.nextInt(5); pot.setText("Pot: "+potBb+" BB"); history.append("\nBot checks to you."); }
    void endHand(){ active=false; showActions(false); next.setVisibility(VISIBLE); }
    void showActions(boolean on){ int v=on?VISIBLE:GONE; fold.setVisibility(v); call.setVisibility(v); raise.setVisibility(v); if(on)next.setVisibility(GONE); }
    void updateStats(){ int acc=decisions==0?0:(int)Math.round(score*100.0/decisions); stats.setText("Score "+score+"   Decisions "+decisions+"   Accuracy "+acc+"%"); }
  }
}
