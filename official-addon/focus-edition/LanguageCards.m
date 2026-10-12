// LanguageCards.m —— 语言学习：十语常用短句推镜片
#import "LanguageCards.h"
#import "MusicBridge.h"
#import "ResearchUI.h"

static NSDictionary *Phrases(void){
    return @{
      @"中文":@[@"你好",@"谢谢",@"多少钱",@"请问洗手间在哪",@"我不太懂",@"请慢一点说",@"再见",@"我爱这个",@"帮帮我",@"现在几点"],
      @"English":@[@"Hello",@"Thank you",@"How much is it?",@"Where is the restroom?",@"I don't understand",@"Please speak slowly",@"Goodbye",@"I love this",@"Help me",@"What time is it?"],
      @"日本語":@[@"こんにちは",@"ありがとう",@"いくらですか",@"トイレはどこですか",@"わかりません",@"ゆっくり話してください",@"さようなら",@"これが好きです",@"助けてください",@"今何時ですか"],
      @"한국어":@[@"안녕하세요",@"감사합니다",@"얼마예요?",@"화장실이 어디예요?",@"모르겠어요",@"천천히 말해 주세요",@"안녕히 가세요",@"이거 좋아해요",@"도와주세요",@"지금 몇 시예요?"],
      @"Français":@[@"Bonjour",@"Merci",@"Combien ça coûte ?",@"Où sont les toilettes ?",@"Je ne comprends pas",@"Parlez lentement, s'il vous plaît",@"Au revoir",@"J'adore ça",@"Aidez-moi",@"Quelle heure est-il ?"],
      @"Deutsch":@[@"Hallo",@"Danke",@"Wie viel kostet das?",@"Wo ist die Toilette?",@"Ich verstehe nicht",@"Bitte sprechen Sie langsam",@"Auf Wiedersehen",@"Das liebe ich",@"Hilf mir",@"Wie spät ist es?"],
      @"Español":@[@"Hola",@"Gracias",@"¿Cuánto cuesta?",@"¿Dónde está el baño?",@"No entiendo",@"Hable despacio, por favor",@"Adiós",@"Me encanta esto",@"Ayúdame",@"¿Qué hora es?"],
      @"Italiano":@[@"Ciao",@"Grazie",@"Quanto costa?",@"Dov'è il bagno?",@"Non capisco",@"Parla lentamente, per favore",@"Arrivederci",@"Adoro questo",@"Aiutami",@"Che ore sono?"],
      @"Русский":@[@"Здравствуйте",@"Спасибо",@"Сколько стоит?",@"Где туалет?",@"Я не понимаю",@"Говорите медленнее",@"До свидания",@"Мне это нравится",@"Помогите",@"Который час?"],
      @"العربية":@[@"مرحبا",@"شكرا",@"كم الثمن؟",@"أين الحمام؟",@"لا أفهم",@"تحدث ببطء من فضلك",@"وداعا",@"أحب هذا",@"ساعدني",@"كم الساعة؟"],
    };
}

@interface TIOLanguageCardsPanel:UITableViewController
@property(nonatomic,strong) NSString *language;
@property(nonatomic,assign) NSInteger playingIndex;
@end
@implementation TIOLanguageCardsPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"语言学习";TIOStyleResearchTable(self);_language=@"English";_playingIndex=-1;self.tableView.tableHeaderView=TIOFeatureHeader(@"十语常用短句 → 镜片",@"选语言、点句子推送到眼镜 8 秒；可自动逐句轮播。",@"character.book.closed");}
- (NSArray<NSString *> *)languages{return Phrases().allKeys;}
- (NSArray<NSString *> *)phrases{return Phrases()[_language]?:@[];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 2;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?1:self.phrases.count;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return s==0?@"语言":@"短句（点击推送眼镜）";}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==1&&_playingIndex>=0?@"轮播中…再次点击可停止":nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    if(ip.section==0){c.textLabel.text=_language;c.detailTextLabel.text=@"点击切换语言";c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
    else{c.textLabel.text=self.phrases[ip.row];c.detailTextLabel.text=_playingIndex==ip.row?@"正在推送…":@"点击推送到眼镜 8 秒";}
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];
    if(ip.section==0){
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"选择语言" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        for(NSString *lang in self.languages)[a addAction:[UIAlertAction actionWithTitle:lang style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){_language=lang;_playingIndex=-1;[t reloadData];}]];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=t;a.popoverPresentationController.sourceRect=[t rectForRowAtIndexPath:ip];[self presentViewController:a animated:YES completion:nil];
    }else{
        if(_playingIndex==ip.row){_playingIndex=-1;[t reloadData];return;}
        NSString *sentence=self.phrases[ip.row];
        TMMusicBridge *bridge=[TMMusicBridge shared];if(bridge.failed)[bridge reset];
        [bridge openWithCover:nil lyrics:@[@{@"ms":@0,@"text":sentence}]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{TMMusicBridge *b=[TMMusicBridge shared];if(![b failed])[b close];});
        _playingIndex=ip.row;[t reloadData];
    }
}
@end
UIViewController *TIOLanguageCardsController(void){return [[TIOLanguageCardsPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
