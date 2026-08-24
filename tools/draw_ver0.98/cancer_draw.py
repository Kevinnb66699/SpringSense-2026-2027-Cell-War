import random

draw_pile = [
    "Invasion【即时】移动3步",
    "Invasion【即时】移动3步",

    "Glucose【即时】生物质+1",
    "Glucose【即时】生物质+1",

    "Maltose【即时】生物质+2",
    "Maltose【即时】生物质+2",

    "Starvation【即时】所有癌细胞生物质+1",
    "Starvation【即时】所有癌细胞生物质+1",

    "Teleporting【即时】传送到棋盘上任意己方阵营的组织上",
    "Teleporting【即时】传送到棋盘上任意己方阵营的组织上",

    "Translocation【即时】和己方阵营的任意队友交换位置",
    "Translocation【即时】和己方阵营的任意队友交换位置",

    "Bad drug【即时】抽两张卡",

    "Mutation【即时】若生物质大于1，则抽三张卡，失去1点生物质",

    "Bad day【即时】将棋盘上任一正常组织转变为普通癌组织",

    "VEGF【即时】将一血管移动1-3步，不能和其他特殊事件重合",

    "Infiltration【即时】本回合获得1次额外移动机会",
    "Infiltration【即时】本回合获得1次额外移动机会",

    "Infinite division【即时】下一次受到攻击不会被击退",
    "Infinite division【即时】下一次受到攻击不会被击退",

    "Keratinization【即时】免疫下一次攻击受到的生物质伤害",
    "Keratinization【即时】免疫下一次攻击受到的生物质伤害",

    "Dodge【即时】逃逸下一次攻击",
    "Dodge【即时】逃逸下一次攻击",

    "Metastasis【能力】每回合的移动阶段开始前可以移动1步",

    "Heavy worker【能力】从墙壁工厂获得的墙壁数量+1",

    "Doom【能力】以自己为中心，感染周围一圈组织，包括当前组织",

    "Nuclear radiation【即时】选择任一普通癌组织，固化该普通癌组织"
]

discard_pile = []

random.shuffle(draw_pile)

print("=== 癌细胞抽卡系统 ===")
print("按 Enter 抽一张牌，输入 q 后回车退出。")

while True:
    command = input("\n继续抽牌？").strip().lower()

    if command == "q":
        print("已退出。")
        break

    if len(draw_pile) == 0:
        print("\n>>> 卡池已抽空，正在将弃牌堆洗回卡池……")
        draw_pile = discard_pile[:]
        discard_pile = []
        random.shuffle(draw_pile)

    card = draw_pile.pop()
    discard_pile.append(card)

    print("\n抽到的卡牌：")
    print(card)
    print(f"\n当前状态：卡池剩余 {len(draw_pile)} 张，弃牌堆 {len(discard_pile)} 张")