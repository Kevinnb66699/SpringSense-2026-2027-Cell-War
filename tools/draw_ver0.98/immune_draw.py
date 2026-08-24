import random

draw_pile = [
    "Diapedesis【即时】移动3步",
    "Diapedesis【即时】移动3步",

    "Glucose【即时】生物质+1",
    "Glucose【即时】生物质+1",

    "Maltose【即时】生物质+2",
    "Maltose【即时】生物质+2",

    "Balanced diet【即时】所有免疫细胞生物质+1",
    "Balanced diet【即时】所有免疫细胞生物质+1",

    "Teleporting【即时】传送到棋盘上任意己方阵营的组织上",
    "Teleporting【即时】传送到棋盘上任意己方阵营的组织上",

    "Translocation【即时】和己方阵营的任意队友交换位置",
    "Translocation【即时】和己方阵营的任意队友交换位置",

    "Good drug【即时】抽两张卡",

    "Evolution【即时】若生物质大于1，则抽三张卡，失去1点生物质",

    "Good day【即时】将棋盘上任一癌组织转变为正常组织",

    "VEGF【即时】将一血管移动1-3步，不能和其他特殊事件重合",

    "Information detection【即时】本回合获得1次额外移动机会",
    "Information detection【即时】本回合获得1次额外移动机会",

    "Complement activation【即时】下一次的攻击范围+1",
    "Complement activation【即时】下一次的攻击范围+1",

    "Cytokine【即时】下一次攻击的攻击力+1",
    "Cytokine【即时】下一次攻击的攻击力+1",

    "Precise recognition【即时】下一次攻击一定成功",
    "Precise recognition【即时】下一次攻击一定成功",

    "Chemotaxis【能力】每回合的移动阶段开始前可以移动1步",

    "Humoral immunity【能力】攻击范围+1",

    "Cell-mediated immunity【能力】攻击力+1",

    "Excalibur【即时】以自己为中心，净化一条直线上的所有癌细胞"
]

discard_pile = []

random.shuffle(draw_pile)

print("=== 免疫细胞抽卡系统 ===")
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