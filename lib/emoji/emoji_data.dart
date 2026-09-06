// The emoji the picker offers, embedded as a Dart constant.
//
// Deliberately dependency-free — no Flutter, no I/O — so the table and everything
// ranked against it are plain unit tests.
//
// **It is a constant rather than an asset, which keeps "the shell ships no image
// assets" true one file over.** Nothing in the shell resolves paths relative to
// the bundle, so a table read from a share dir would work under `flutter run` and
// not under `make install` or the snap. Unicode's own `emoji-test.txt` is the
// obvious alternative and wrong twice over: four thousand entries to page through
// for a smiley, and CLDR *names* alone, where the point of this search is the
// **keywords** a person types ("lol", "party", "wfh").
//
// The set is curated rather than exhaustive: a shell's quick picker is for the
// emoji somebody reaches for in a message.
library;

/// The groups the table is written in, and the coarsest of the four dimensions
/// the search matches on — typing "food" is a legitimate way to ask for pizza.
///
/// [label] is what the picker prints under a selected emoji; [terms] are the extra
/// words that mean the same group, because "nature" and "plants" are both
/// reasonable ways to ask for a leaf.
enum EmojiCategory {
  smileys('Smileys & Emotion', ['face', 'emotion', 'smiley']),
  people('People & Body', ['person', 'body', 'hand', 'gesture']),
  animals('Animals & Nature', ['nature', 'animal', 'plant']),
  food('Food & Drink', ['food', 'drink', 'eat']),
  activities('Activities', ['activity', 'sport', 'game', 'celebration']),
  travel('Travel & Places', ['travel', 'place', 'vehicle']),
  objects('Objects', ['object', 'thing', 'tool']),
  symbols('Symbols', ['symbol', 'sign', 'mark']),
  flags('Flags', ['flag', 'country']);

  const EmojiCategory(this.label, this.terms);

  /// The heading the picker shows.
  final String label;

  /// Words that also name this group, beyond the ones already in [label].
  final List<String> terms;
}

/// One emoji and every dimension the picker searches it by.
///
/// All four are searched (see `emoji_search.dart`) — the character itself
/// included, so pasting an emoji back into the field finds it.
class Emoji {
  const Emoji(this.char, this.name, this.category, this.keywords);

  /// The character to copy. May be several code points (a ZWJ sequence, a
  /// flag's regional-indicator pair), which is why nothing here indexes by
  /// code unit.
  final String char;

  /// The name shown under the selection, and the highest-weighted dimension.
  final String name;

  final EmojiCategory category;

  /// What somebody might type instead of the name. This is the dimension the
  /// table exists for: "lol", "wfh", "shrug" and "thanks" are how people
  /// actually search, and none of them is anybody's *name* for an emoji.
  final List<String> keywords;
}

/// The table, in the order an empty query shows it: grouped by category, and
/// within a group roughly by how often the emoji is reached for.
///
/// A new entry needs a name and at least one keyword somebody would type that the
/// name does not already contain.
const List<Emoji> kEmoji = [
  // ---- Smileys & Emotion -------------------------------------------------
  Emoji('😀', 'grinning face', EmojiCategory.smileys, [
    'happy',
    'smile',
    'grin',
  ]),
  Emoji('😃', 'grinning face with big eyes', EmojiCategory.smileys, [
    'happy',
    'smile',
    'joy',
  ]),
  Emoji('😄', 'grinning face with smiling eyes', EmojiCategory.smileys, [
    'happy',
    'smile',
    'laugh',
  ]),
  Emoji('😁', 'beaming face with smiling eyes', EmojiCategory.smileys, [
    'happy',
    'grin',
    'teeth',
  ]),
  Emoji('😆', 'grinning squinting face', EmojiCategory.smileys, [
    'laugh',
    'haha',
    'squint',
  ]),
  Emoji('😅', 'grinning face with sweat', EmojiCategory.smileys, [
    'relief',
    'phew',
    'nervous',
    'laugh',
  ]),
  Emoji('😂', 'face with tears of joy', EmojiCategory.smileys, [
    'lol',
    'laugh',
    'cry',
    'funny',
  ]),
  Emoji('🤣', 'rolling on the floor laughing', EmojiCategory.smileys, [
    'rofl',
    'lol',
    'laugh',
    'funny',
  ]),
  Emoji('🙂', 'slightly smiling face', EmojiCategory.smileys, [
    'smile',
    'polite',
    'fine',
  ]),
  Emoji('🙃', 'upside-down face', EmojiCategory.smileys, [
    'sarcasm',
    'irony',
    'silly',
  ]),
  Emoji('😉', 'winking face', EmojiCategory.smileys, ['wink', 'flirt', 'joke']),
  Emoji('😊', 'smiling face with smiling eyes', EmojiCategory.smileys, [
    'blush',
    'happy',
    'shy',
  ]),
  Emoji('😇', 'smiling face with halo', EmojiCategory.smileys, [
    'angel',
    'innocent',
    'good',
  ]),
  Emoji('🥰', 'smiling face with hearts', EmojiCategory.smileys, [
    'love',
    'adore',
    'crush',
  ]),
  Emoji('😍', 'smiling face with heart-eyes', EmojiCategory.smileys, [
    'love',
    'crush',
    'adore',
  ]),
  Emoji('🤩', 'star-struck', EmojiCategory.smileys, [
    'starry',
    'amazed',
    'wow',
    'excited',
  ]),
  Emoji('😘', 'face blowing a kiss', EmojiCategory.smileys, [
    'kiss',
    'love',
    'xoxo',
  ]),
  Emoji('😗', 'kissing face', EmojiCategory.smileys, ['kiss', 'whistle']),
  Emoji('😚', 'kissing face with closed eyes', EmojiCategory.smileys, [
    'kiss',
    'love',
  ]),
  Emoji('😋', 'face savoring food', EmojiCategory.smileys, [
    'yum',
    'tasty',
    'delicious',
    'tongue',
  ]),
  Emoji('😛', 'face with tongue', EmojiCategory.smileys, [
    'tongue',
    'cheeky',
    'silly',
  ]),
  Emoji('😜', 'winking face with tongue', EmojiCategory.smileys, [
    'silly',
    'crazy',
    'joke',
  ]),
  Emoji('🤪', 'zany face', EmojiCategory.smileys, ['crazy', 'goofy', 'wild']),
  Emoji('😝', 'squinting face with tongue', EmojiCategory.smileys, [
    'tongue',
    'silly',
    'taunt',
  ]),
  Emoji('🤑', 'money-mouth face', EmojiCategory.smileys, [
    'money',
    'rich',
    'dollar',
    'greedy',
  ]),
  Emoji('🤗', 'smiling face with open hands', EmojiCategory.smileys, [
    'hug',
    'welcome',
    'embrace',
  ]),
  Emoji('🤭', 'face with hand over mouth', EmojiCategory.smileys, [
    'oops',
    'giggle',
    'secret',
  ]),
  Emoji('🤫', 'shushing face', EmojiCategory.smileys, [
    'quiet',
    'shh',
    'secret',
    'silence',
  ]),
  Emoji('🤔', 'thinking face', EmojiCategory.smileys, [
    'hmm',
    'think',
    'consider',
    'ponder',
  ]),
  Emoji('🤐', 'zipper-mouth face', EmojiCategory.smileys, [
    'quiet',
    'secret',
    'sealed',
  ]),
  Emoji('🤨', 'face with raised eyebrow', EmojiCategory.smileys, [
    'skeptic',
    'doubt',
    'suspicious',
  ]),
  Emoji('😐', 'neutral face', EmojiCategory.smileys, [
    'meh',
    'blank',
    'deadpan',
  ]),
  Emoji('😑', 'expressionless face', EmojiCategory.smileys, [
    'blank',
    'meh',
    'unimpressed',
  ]),
  Emoji('😶', 'face without mouth', EmojiCategory.smileys, [
    'speechless',
    'silent',
    'blank',
  ]),
  Emoji('😏', 'smirking face', EmojiCategory.smileys, ['smirk', 'smug', 'sly']),
  Emoji('😒', 'unamused face', EmojiCategory.smileys, [
    'meh',
    'unimpressed',
    'annoyed',
  ]),
  Emoji('🙄', 'face with rolling eyes', EmojiCategory.smileys, [
    'eyeroll',
    'whatever',
    'annoyed',
  ]),
  Emoji('😬', 'grimacing face', EmojiCategory.smileys, [
    'awkward',
    'eek',
    'yikes',
    'cringe',
  ]),
  Emoji('😮‍💨', 'face exhaling', EmojiCategory.smileys, [
    'sigh',
    'relief',
    'exhale',
    'phew',
  ]),
  Emoji('🤥', 'lying face', EmojiCategory.smileys, [
    'lie',
    'pinocchio',
    'liar',
  ]),
  Emoji('😌', 'relieved face', EmojiCategory.smileys, [
    'relief',
    'calm',
    'content',
  ]),
  Emoji('😔', 'pensive face', EmojiCategory.smileys, [
    'sad',
    'down',
    'dejected',
  ]),
  Emoji('😪', 'sleepy face', EmojiCategory.smileys, [
    'tired',
    'sleep',
    'exhausted',
  ]),
  Emoji('🤤', 'drooling face', EmojiCategory.smileys, [
    'drool',
    'want',
    'hungry',
  ]),
  Emoji('😴', 'sleeping face', EmojiCategory.smileys, [
    'sleep',
    'zzz',
    'tired',
    'bed',
  ]),
  Emoji('😷', 'face with medical mask', EmojiCategory.smileys, [
    'mask',
    'sick',
    'ill',
  ]),
  Emoji('🤒', 'face with thermometer', EmojiCategory.smileys, [
    'sick',
    'fever',
    'ill',
  ]),
  Emoji('🤕', 'face with head-bandage', EmojiCategory.smileys, [
    'hurt',
    'injured',
    'ouch',
  ]),
  Emoji('🤢', 'nauseated face', EmojiCategory.smileys, ['sick', 'gross', 'ew']),
  Emoji('🤮', 'face vomiting', EmojiCategory.smileys, [
    'sick',
    'vomit',
    'gross',
    'puke',
  ]),
  Emoji('🤧', 'sneezing face', EmojiCategory.smileys, [
    'sneeze',
    'cold',
    'tissue',
  ]),
  Emoji('🥵', 'hot face', EmojiCategory.smileys, ['heat', 'sweat', 'warm']),
  Emoji('🥶', 'cold face', EmojiCategory.smileys, ['freezing', 'ice', 'brr']),
  Emoji('🥴', 'woozy face', EmojiCategory.smileys, ['dizzy', 'drunk', 'tipsy']),
  Emoji('😵', 'face with crossed-out eyes', EmojiCategory.smileys, [
    'dead',
    'dizzy',
    'knocked out',
  ]),
  Emoji('🤯', 'exploding head', EmojiCategory.smileys, [
    'mindblown',
    'shocked',
    'wow',
  ]),
  Emoji('🤠', 'cowboy hat face', EmojiCategory.smileys, [
    'cowboy',
    'yeehaw',
    'hat',
  ]),
  Emoji('🥳', 'partying face', EmojiCategory.smileys, [
    'party',
    'celebrate',
    'birthday',
  ]),
  Emoji('🥸', 'disguised face', EmojiCategory.smileys, [
    'disguise',
    'incognito',
    'glasses',
  ]),
  Emoji('😎', 'smiling face with sunglasses', EmojiCategory.smileys, [
    'cool',
    'sunglasses',
    'deal with it',
  ]),
  Emoji('🤓', 'nerd face', EmojiCategory.smileys, [
    'nerd',
    'geek',
    'glasses',
    'smart',
  ]),
  Emoji('🧐', 'face with monocle', EmojiCategory.smileys, [
    'monocle',
    'inspect',
    'scrutiny',
  ]),
  Emoji('😕', 'confused face', EmojiCategory.smileys, [
    'confused',
    'puzzled',
    'unsure',
  ]),
  Emoji('😟', 'worried face', EmojiCategory.smileys, [
    'worry',
    'concern',
    'anxious',
  ]),
  Emoji('🙁', 'slightly frowning face', EmojiCategory.smileys, [
    'sad',
    'frown',
    'unhappy',
  ]),
  Emoji('😮', 'face with open mouth', EmojiCategory.smileys, [
    'surprise',
    'wow',
    'shock',
  ]),
  Emoji('😯', 'hushed face', EmojiCategory.smileys, [
    'surprise',
    'quiet',
    'stunned',
  ]),
  Emoji('😲', 'astonished face', EmojiCategory.smileys, [
    'shock',
    'gasp',
    'amazed',
  ]),
  Emoji('😳', 'flushed face', EmojiCategory.smileys, [
    'blush',
    'embarrassed',
    'shy',
  ]),
  Emoji('🥺', 'pleading face', EmojiCategory.smileys, [
    'please',
    'beg',
    'puppy eyes',
  ]),
  Emoji('😦', 'frowning face with open mouth', EmojiCategory.smileys, [
    'sad',
    'shock',
    'dismay',
  ]),
  Emoji('😨', 'fearful face', EmojiCategory.smileys, [
    'scared',
    'fear',
    'afraid',
  ]),
  Emoji('😰', 'anxious face with sweat', EmojiCategory.smileys, [
    'nervous',
    'anxious',
    'worried',
  ]),
  Emoji('😥', 'sad but relieved face', EmojiCategory.smileys, [
    'phew',
    'sad',
    'relief',
  ]),
  Emoji('😢', 'crying face', EmojiCategory.smileys, ['cry', 'sad', 'tear']),
  Emoji('😭', 'loudly crying face', EmojiCategory.smileys, [
    'sob',
    'cry',
    'bawling',
    'sad',
  ]),
  Emoji('😱', 'face screaming in fear', EmojiCategory.smileys, [
    'scream',
    'shock',
    'horror',
  ]),
  Emoji('😖', 'confounded face', EmojiCategory.smileys, [
    'frustrated',
    'ugh',
    'confused',
  ]),
  Emoji('😣', 'persevering face', EmojiCategory.smileys, [
    'struggle',
    'strain',
    'ugh',
  ]),
  Emoji('😞', 'disappointed face', EmojiCategory.smileys, [
    'sad',
    'let down',
    'unhappy',
  ]),
  Emoji('😓', 'downcast face with sweat', EmojiCategory.smileys, [
    'sad',
    'sweat',
    'hard work',
  ]),
  Emoji('😩', 'weary face', EmojiCategory.smileys, [
    'tired',
    'exhausted',
    'ugh',
  ]),
  Emoji('😫', 'tired face', EmojiCategory.smileys, [
    'exhausted',
    'ugh',
    'fed up',
  ]),
  Emoji('🥱', 'yawning face', EmojiCategory.smileys, [
    'yawn',
    'bored',
    'tired',
  ]),
  Emoji('😤', 'face with steam from nose', EmojiCategory.smileys, [
    'triumph',
    'determined',
    'huff',
  ]),
  Emoji('😡', 'enraged face', EmojiCategory.smileys, ['angry', 'mad', 'rage']),
  Emoji('😠', 'angry face', EmojiCategory.smileys, [
    'mad',
    'annoyed',
    'grumpy',
  ]),
  Emoji('🤬', 'face with symbols on mouth', EmojiCategory.smileys, [
    'swear',
    'curse',
    'angry',
  ]),
  Emoji('😈', 'smiling face with horns', EmojiCategory.smileys, [
    'devil',
    'evil',
    'mischief',
  ]),
  Emoji('👿', 'angry face with horns', EmojiCategory.smileys, [
    'devil',
    'imp',
    'evil',
  ]),
  Emoji('💀', 'skull', EmojiCategory.smileys, ['dead', 'death', 'skeleton']),
  Emoji('💩', 'pile of poo', EmojiCategory.smileys, [
    'poop',
    'crap',
    'rubbish',
  ]),
  Emoji('🤡', 'clown face', EmojiCategory.smileys, ['clown', 'joker', 'fool']),
  Emoji('👻', 'ghost', EmojiCategory.smileys, ['spooky', 'halloween', 'boo']),
  Emoji('👽', 'alien', EmojiCategory.smileys, [
    'ufo',
    'extraterrestrial',
    'space',
  ]),
  Emoji('🤖', 'robot', EmojiCategory.smileys, [
    'bot',
    'android',
    'machine',
    'ai',
  ]),
  Emoji('🎃', 'jack-o-lantern', EmojiCategory.smileys, [
    'halloween',
    'pumpkin',
    'spooky',
  ]),
  Emoji('😺', 'grinning cat', EmojiCategory.smileys, ['cat', 'happy', 'smile']),
  Emoji('😹', 'cat with tears of joy', EmojiCategory.smileys, [
    'cat',
    'lol',
    'laugh',
  ]),
  Emoji('😻', 'smiling cat with heart-eyes', EmojiCategory.smileys, [
    'cat',
    'love',
    'adore',
  ]),
  Emoji('🙀', 'weary cat', EmojiCategory.smileys, ['cat', 'shock', 'surprise']),
  Emoji('😿', 'crying cat', EmojiCategory.smileys, ['cat', 'sad', 'cry']),

  // ---- People & Body -----------------------------------------------------
  Emoji('👋', 'waving hand', EmojiCategory.people, [
    'wave',
    'hello',
    'bye',
    'hi',
  ]),
  Emoji('🤚', 'raised back of hand', EmojiCategory.people, [
    'hand',
    'stop',
    'raised',
  ]),
  Emoji('✋', 'raised hand', EmojiCategory.people, [
    'stop',
    'high five',
    'hand',
  ]),
  Emoji('🖖', 'vulcan salute', EmojiCategory.people, [
    'spock',
    'star trek',
    'live long',
  ]),
  Emoji('👌', 'OK hand', EmojiCategory.people, ['ok', 'perfect', 'fine']),
  Emoji('🤌', 'pinched fingers', EmojiCategory.people, [
    'italian',
    'chef kiss',
    'gesture',
  ]),
  Emoji('🤏', 'pinching hand', EmojiCategory.people, [
    'small',
    'tiny',
    'little',
  ]),
  Emoji('✌️', 'victory hand', EmojiCategory.people, ['peace', 'two', 'v']),
  Emoji('🤞', 'crossed fingers', EmojiCategory.people, [
    'luck',
    'hope',
    'fingers crossed',
  ]),
  Emoji('🤟', 'love-you gesture', EmojiCategory.people, [
    'ily',
    'love',
    'sign',
  ]),
  Emoji('🤘', 'sign of the horns', EmojiCategory.people, [
    'rock',
    'metal',
    'horns',
  ]),
  Emoji('🤙', 'call me hand', EmojiCategory.people, [
    'shaka',
    'hang loose',
    'call',
  ]),
  Emoji('👈', 'backhand index pointing left', EmojiCategory.people, [
    'left',
    'point',
    'this way',
  ]),
  Emoji('👉', 'backhand index pointing right', EmojiCategory.people, [
    'right',
    'point',
    'this way',
  ]),
  Emoji('👆', 'backhand index pointing up', EmojiCategory.people, [
    'up',
    'point',
    'above',
  ]),
  Emoji('👇', 'backhand index pointing down', EmojiCategory.people, [
    'down',
    'point',
    'below',
  ]),
  Emoji('☝️', 'index pointing up', EmojiCategory.people, [
    'one',
    'point',
    'attention',
  ]),
  Emoji('👍', 'thumbs up', EmojiCategory.people, [
    'yes',
    'like',
    'approve',
    'lgtm',
    '+1',
  ]),
  Emoji('👎', 'thumbs down', EmojiCategory.people, [
    'no',
    'dislike',
    'disapprove',
    '-1',
  ]),
  Emoji('✊', 'raised fist', EmojiCategory.people, [
    'fist',
    'power',
    'solidarity',
  ]),
  Emoji('👊', 'oncoming fist', EmojiCategory.people, [
    'punch',
    'fist bump',
    'bro',
  ]),
  Emoji('👏', 'clapping hands', EmojiCategory.people, [
    'applause',
    'clap',
    'bravo',
    'well done',
  ]),
  Emoji('🙌', 'raising hands', EmojiCategory.people, [
    'celebrate',
    'hooray',
    'praise',
  ]),
  Emoji('👐', 'open hands', EmojiCategory.people, ['hug', 'open', 'welcome']),
  Emoji('🤲', 'palms up together', EmojiCategory.people, [
    'pray',
    'please',
    'offer',
  ]),
  Emoji('🤝', 'handshake', EmojiCategory.people, [
    'deal',
    'agree',
    'shake',
    'partnership',
  ]),
  Emoji('🙏', 'folded hands', EmojiCategory.people, [
    'thanks',
    'please',
    'pray',
    'thank you',
  ]),
  Emoji('✍️', 'writing hand', EmojiCategory.people, ['write', 'sign', 'pen']),
  Emoji('💪', 'flexed biceps', EmojiCategory.people, [
    'strong',
    'muscle',
    'gym',
    'power',
  ]),
  Emoji('🦾', 'mechanical arm', EmojiCategory.people, [
    'prosthetic',
    'robot',
    'strong',
  ]),
  Emoji('🧠', 'brain', EmojiCategory.people, [
    'smart',
    'mind',
    'think',
    'intelligence',
  ]),
  Emoji('👀', 'eyes', EmojiCategory.people, ['look', 'watch', 'see', 'shifty']),
  Emoji('👁️', 'eye', EmojiCategory.people, ['look', 'see', 'watch']),
  Emoji('👄', 'mouth', EmojiCategory.people, ['lips', 'kiss', 'talk']),
  Emoji('👶', 'baby', EmojiCategory.people, ['infant', 'child', 'newborn']),
  Emoji('🧒', 'child', EmojiCategory.people, ['kid', 'young']),
  Emoji('👦', 'boy', EmojiCategory.people, ['kid', 'child', 'young']),
  Emoji('👧', 'girl', EmojiCategory.people, ['kid', 'child', 'young']),
  Emoji('🧑', 'person', EmojiCategory.people, ['adult', 'human', 'someone']),
  Emoji('👨', 'man', EmojiCategory.people, ['male', 'adult', 'guy']),
  Emoji('👩', 'woman', EmojiCategory.people, ['female', 'adult', 'lady']),
  Emoji('🧓', 'older person', EmojiCategory.people, ['elder', 'senior', 'old']),
  Emoji('🧔', 'person with beard', EmojiCategory.people, [
    'beard',
    'facial hair',
  ]),
  Emoji('👮', 'police officer', EmojiCategory.people, ['cop', 'police', 'law']),
  Emoji('🕵️', 'detective', EmojiCategory.people, [
    'spy',
    'investigate',
    'sleuth',
  ]),
  Emoji('👷', 'construction worker', EmojiCategory.people, [
    'builder',
    'hardhat',
    'work',
  ]),
  Emoji('🧑‍⚕️', 'health worker', EmojiCategory.people, [
    'doctor',
    'nurse',
    'medical',
  ]),
  Emoji('🧑‍💻', 'technologist', EmojiCategory.people, [
    'developer',
    'programmer',
    'coder',
    'wfh',
  ]),
  Emoji('🧑‍🍳', 'cook', EmojiCategory.people, ['chef', 'kitchen', 'cooking']),
  Emoji('🧑‍🚀', 'astronaut', EmojiCategory.people, [
    'space',
    'nasa',
    'rocket',
  ]),
  Emoji('🥷', 'ninja', EmojiCategory.people, [
    'stealth',
    'shinobi',
    'assassin',
  ]),
  Emoji('🤴', 'prince', EmojiCategory.people, ['royal', 'crown']),
  Emoji('👸', 'princess', EmojiCategory.people, ['royal', 'crown', 'queen']),
  Emoji('🦸', 'superhero', EmojiCategory.people, ['hero', 'super', 'cape']),
  Emoji('🦹', 'supervillain', EmojiCategory.people, [
    'villain',
    'evil',
    'bad guy',
  ]),
  Emoji('🎅', 'Santa Claus', EmojiCategory.people, [
    'christmas',
    'xmas',
    'father christmas',
  ]),
  Emoji('🧙', 'mage', EmojiCategory.people, ['wizard', 'magic', 'sorcerer']),
  Emoji('🧚', 'fairy', EmojiCategory.people, ['magic', 'pixie', 'wings']),
  Emoji('🧟', 'zombie', EmojiCategory.people, [
    'undead',
    'halloween',
    'walker',
  ]),
  Emoji('💁', 'person tipping hand', EmojiCategory.people, [
    'sassy',
    'information',
    'help desk',
  ]),
  Emoji('🙋', 'person raising hand', EmojiCategory.people, [
    'volunteer',
    'question',
    'here',
  ]),
  Emoji('🙇', 'person bowing', EmojiCategory.people, [
    'sorry',
    'bow',
    'apology',
    'respect',
  ]),
  Emoji('🤦', 'person facepalming', EmojiCategory.people, [
    'facepalm',
    'disbelief',
    'ugh',
  ]),
  Emoji('🤷', 'person shrugging', EmojiCategory.people, [
    'shrug',
    'dunno',
    'whatever',
    'idk',
  ]),
  Emoji('💃', 'woman dancing', EmojiCategory.people, [
    'dance',
    'party',
    'flamenco',
  ]),
  Emoji('🕺', 'man dancing', EmojiCategory.people, ['dance', 'party', 'disco']),
  Emoji('🚶', 'person walking', EmojiCategory.people, [
    'walk',
    'stroll',
    'pedestrian',
  ]),
  Emoji('🏃', 'person running', EmojiCategory.people, [
    'run',
    'sprint',
    'exercise',
    'late',
  ]),
  Emoji('🧘', 'person in lotus position', EmojiCategory.people, [
    'yoga',
    'meditate',
    'calm',
    'zen',
  ]),
  Emoji('🛀', 'person taking bath', EmojiCategory.people, [
    'bath',
    'relax',
    'wash',
  ]),
  Emoji('👪', 'family', EmojiCategory.people, ['parents', 'kids', 'home']),
  Emoji('🫂', 'people hugging', EmojiCategory.people, [
    'hug',
    'support',
    'comfort',
  ]),

  // ---- Animals & Nature --------------------------------------------------
  Emoji('🐶', 'dog face', EmojiCategory.animals, ['puppy', 'pet', 'woof']),
  Emoji('🐱', 'cat face', EmojiCategory.animals, ['kitten', 'pet', 'meow']),
  Emoji('🐭', 'mouse face', EmojiCategory.animals, ['rodent', 'squeak']),
  Emoji('🐹', 'hamster', EmojiCategory.animals, ['pet', 'rodent']),
  Emoji('🐰', 'rabbit face', EmojiCategory.animals, [
    'bunny',
    'hare',
    'easter',
  ]),
  Emoji('🦊', 'fox', EmojiCategory.animals, ['sly', 'firefox']),
  Emoji('🐻', 'bear', EmojiCategory.animals, ['grizzly', 'wild']),
  Emoji('🐼', 'panda', EmojiCategory.animals, ['bear', 'china', 'bamboo']),
  Emoji('🐨', 'koala', EmojiCategory.animals, ['australia', 'marsupial']),
  Emoji('🐯', 'tiger face', EmojiCategory.animals, ['big cat', 'stripes']),
  Emoji('🦁', 'lion', EmojiCategory.animals, ['king', 'big cat', 'roar']),
  Emoji('🐮', 'cow face', EmojiCategory.animals, ['moo', 'cattle', 'farm']),
  Emoji('🐷', 'pig face', EmojiCategory.animals, ['oink', 'farm', 'hog']),
  Emoji('🐸', 'frog', EmojiCategory.animals, ['toad', 'ribbit', 'amphibian']),
  Emoji('🐵', 'monkey face', EmojiCategory.animals, ['ape', 'primate']),
  Emoji('🙈', 'see-no-evil monkey', EmojiCategory.animals, [
    'embarrassed',
    'hide',
    'oops',
  ]),
  Emoji('🙉', 'hear-no-evil monkey', EmojiCategory.animals, [
    'ignore',
    'deaf',
    'monkey',
  ]),
  Emoji('🙊', 'speak-no-evil monkey', EmojiCategory.animals, [
    'secret',
    'quiet',
    'oops',
  ]),
  Emoji('🐔', 'chicken', EmojiCategory.animals, ['hen', 'farm', 'cluck']),
  Emoji('🐧', 'penguin', EmojiCategory.animals, [
    'linux',
    'tux',
    'antarctic',
    'bird',
  ]),
  Emoji('🐦', 'bird', EmojiCategory.animals, ['tweet', 'fly', 'wings']),
  Emoji('🦆', 'duck', EmojiCategory.animals, ['quack', 'bird', 'pond']),
  Emoji('🦉', 'owl', EmojiCategory.animals, ['wise', 'night', 'bird']),
  Emoji('🦇', 'bat', EmojiCategory.animals, ['vampire', 'night', 'halloween']),
  Emoji('🐺', 'wolf', EmojiCategory.animals, ['howl', 'wild', 'pack']),
  Emoji('🐗', 'boar', EmojiCategory.animals, ['pig', 'wild', 'tusk']),
  Emoji('🐴', 'horse face', EmojiCategory.animals, ['pony', 'neigh', 'equine']),
  Emoji('🦄', 'unicorn', EmojiCategory.animals, [
    'magic',
    'fantasy',
    'rainbow',
  ]),
  Emoji('🐝', 'honeybee', EmojiCategory.animals, ['bee', 'buzz', 'honey']),
  Emoji('🐛', 'bug', EmojiCategory.animals, [
    'insect',
    'caterpillar',
    'defect',
  ]),
  Emoji('🦋', 'butterfly', EmojiCategory.animals, [
    'insect',
    'wings',
    'pretty',
  ]),
  Emoji('🐌', 'snail', EmojiCategory.animals, ['slow', 'shell']),
  Emoji('🐞', 'lady beetle', EmojiCategory.animals, [
    'ladybug',
    'insect',
    'luck',
  ]),
  Emoji('🐜', 'ant', EmojiCategory.animals, ['insect', 'work', 'colony']),
  Emoji('🕷️', 'spider', EmojiCategory.animals, [
    'web',
    'arachnid',
    'halloween',
  ]),
  Emoji('🦂', 'scorpion', EmojiCategory.animals, ['sting', 'arachnid']),
  Emoji('🐢', 'turtle', EmojiCategory.animals, ['slow', 'tortoise', 'shell']),
  Emoji('🐍', 'snake', EmojiCategory.animals, ['python', 'serpent', 'hiss']),
  Emoji('🦎', 'lizard', EmojiCategory.animals, ['gecko', 'reptile']),
  Emoji('🦖', 'T-Rex', EmojiCategory.animals, ['dinosaur', 'dino', 'rawr']),
  Emoji('🐙', 'octopus', EmojiCategory.animals, [
    'tentacles',
    'sea',
    'cephalopod',
  ]),
  Emoji('🦑', 'squid', EmojiCategory.animals, ['sea', 'calamari', 'tentacles']),
  Emoji('🦀', 'crab', EmojiCategory.animals, ['rust', 'shellfish', 'claw']),
  Emoji('🐟', 'fish', EmojiCategory.animals, ['sea', 'swim', 'ocean']),
  Emoji('🐠', 'tropical fish', EmojiCategory.animals, [
    'reef',
    'aquarium',
    'sea',
  ]),
  Emoji('🐬', 'dolphin', EmojiCategory.animals, ['sea', 'flipper', 'ocean']),
  Emoji('🐳', 'spouting whale', EmojiCategory.animals, [
    'docker',
    'sea',
    'ocean',
  ]),
  Emoji('🦈', 'shark', EmojiCategory.animals, ['jaws', 'sea', 'fin']),
  Emoji('🐊', 'crocodile', EmojiCategory.animals, ['alligator', 'reptile']),
  Emoji('🐘', 'elephant', EmojiCategory.animals, ['trunk', 'big', 'memory']),
  Emoji('🦒', 'giraffe', EmojiCategory.animals, ['tall', 'neck', 'safari']),
  Emoji('🦓', 'zebra', EmojiCategory.animals, ['stripes', 'safari']),
  Emoji('🐑', 'ewe', EmojiCategory.animals, ['sheep', 'wool', 'baa']),
  Emoji('🐐', 'goat', EmojiCategory.animals, ['greatest', 'farm', 'bleat']),
  Emoji('🐕', 'dog', EmojiCategory.animals, ['pet', 'canine', 'walk']),
  Emoji('🦮', 'guide dog', EmojiCategory.animals, [
    'service',
    'blind',
    'assistance',
  ]),
  Emoji('🐈', 'cat', EmojiCategory.animals, ['pet', 'feline']),
  Emoji('🐇', 'rabbit', EmojiCategory.animals, ['bunny', 'hop', 'hare']),
  Emoji('🦥', 'sloth', EmojiCategory.animals, ['slow', 'lazy', 'hang']),
  Emoji('🦔', 'hedgehog', EmojiCategory.animals, ['spiky', 'sonic']),
  Emoji('🌵', 'cactus', EmojiCategory.animals, [
    'desert',
    'plant',
    'succulent',
  ]),
  Emoji('🌲', 'evergreen tree', EmojiCategory.animals, [
    'pine',
    'forest',
    'conifer',
  ]),
  Emoji('🌳', 'deciduous tree', EmojiCategory.animals, [
    'tree',
    'forest',
    'oak',
  ]),
  Emoji('🌴', 'palm tree', EmojiCategory.animals, [
    'beach',
    'tropical',
    'holiday',
  ]),
  Emoji('🌱', 'seedling', EmojiCategory.animals, [
    'sprout',
    'grow',
    'new',
    'plant',
  ]),
  Emoji('🌿', 'herb', EmojiCategory.animals, ['leaf', 'plant', 'green']),
  Emoji('☘️', 'shamrock', EmojiCategory.animals, ['clover', 'irish', 'luck']),
  Emoji('🍀', 'four leaf clover', EmojiCategory.animals, [
    'luck',
    'lucky',
    'irish',
  ]),
  Emoji('🍁', 'maple leaf', EmojiCategory.animals, [
    'canada',
    'autumn',
    'fall',
  ]),
  Emoji('🍂', 'fallen leaf', EmojiCategory.animals, [
    'autumn',
    'fall',
    'leaves',
  ]),
  Emoji('🌷', 'tulip', EmojiCategory.animals, ['flower', 'spring', 'bloom']),
  Emoji('🌹', 'rose', EmojiCategory.animals, ['flower', 'love', 'romance']),
  Emoji('🌻', 'sunflower', EmojiCategory.animals, ['flower', 'sun', 'yellow']),
  Emoji('🌸', 'cherry blossom', EmojiCategory.animals, [
    'sakura',
    'spring',
    'flower',
  ]),
  Emoji('💐', 'bouquet', EmojiCategory.animals, [
    'flowers',
    'gift',
    'congrats',
  ]),
  Emoji('🌍', 'globe showing Europe-Africa', EmojiCategory.animals, [
    'earth',
    'world',
    'planet',
  ]),
  Emoji('🌎', 'globe showing Americas', EmojiCategory.animals, [
    'earth',
    'world',
    'planet',
  ]),
  Emoji('🌏', 'globe showing Asia-Australia', EmojiCategory.animals, [
    'earth',
    'world',
    'planet',
  ]),
  Emoji('🌞', 'sun with face', EmojiCategory.animals, [
    'sunny',
    'day',
    'bright',
  ]),
  Emoji('🌝', 'full moon face', EmojiCategory.animals, [
    'moon',
    'night',
    'lunar',
  ]),
  Emoji('🌚', 'new moon face', EmojiCategory.animals, [
    'moon',
    'dark',
    'night',
  ]),
  Emoji('⭐', 'star', EmojiCategory.animals, ['favourite', 'night', 'rating']),
  Emoji('🌟', 'glowing star', EmojiCategory.animals, [
    'sparkle',
    'shine',
    'special',
  ]),
  Emoji('✨', 'sparkles', EmojiCategory.animals, [
    'shiny',
    'magic',
    'clean',
    'new',
  ]),
  Emoji('⚡', 'high voltage', EmojiCategory.animals, [
    'lightning',
    'fast',
    'power',
    'zap',
  ]),
  Emoji('🔥', 'fire', EmojiCategory.animals, ['hot', 'lit', 'flame', 'burn']),
  Emoji('💧', 'droplet', EmojiCategory.animals, ['water', 'drop', 'sweat']),
  Emoji('🌊', 'water wave', EmojiCategory.animals, ['sea', 'ocean', 'surf']),
  Emoji('☀️', 'sun', EmojiCategory.animals, ['sunny', 'clear', 'weather']),
  Emoji('⛅', 'sun behind cloud', EmojiCategory.animals, [
    'partly cloudy',
    'weather',
  ]),
  Emoji('☁️', 'cloud', EmojiCategory.animals, [
    'cloudy',
    'weather',
    'overcast',
  ]),
  Emoji('🌧️', 'cloud with rain', EmojiCategory.animals, [
    'rain',
    'weather',
    'wet',
  ]),
  Emoji('⛈️', 'cloud with lightning and rain', EmojiCategory.animals, [
    'storm',
    'thunder',
    'weather',
  ]),
  Emoji('❄️', 'snowflake', EmojiCategory.animals, ['snow', 'cold', 'winter']),
  Emoji('⛄', 'snowman without snow', EmojiCategory.animals, [
    'winter',
    'snow',
    'cold',
  ]),
  Emoji('🌈', 'rainbow', EmojiCategory.animals, [
    'pride',
    'colours',
    'weather',
  ]),
  Emoji('🌙', 'crescent moon', EmojiCategory.animals, [
    'night',
    'lunar',
    'sleep',
  ]),

  // ---- Food & Drink ------------------------------------------------------
  Emoji('🍎', 'red apple', EmojiCategory.food, ['fruit', 'healthy']),
  Emoji('🍊', 'tangerine', EmojiCategory.food, ['orange', 'fruit', 'citrus']),
  Emoji('🍋', 'lemon', EmojiCategory.food, ['citrus', 'sour', 'fruit']),
  Emoji('🍌', 'banana', EmojiCategory.food, ['fruit', 'yellow']),
  Emoji('🍉', 'watermelon', EmojiCategory.food, ['fruit', 'summer', 'melon']),
  Emoji('🍇', 'grapes', EmojiCategory.food, ['fruit', 'wine', 'vine']),
  Emoji('🍓', 'strawberry', EmojiCategory.food, ['fruit', 'berry', 'sweet']),
  Emoji('🫐', 'blueberries', EmojiCategory.food, ['fruit', 'berry']),
  Emoji('🍒', 'cherries', EmojiCategory.food, ['fruit', 'berry', 'red']),
  Emoji('🍑', 'peach', EmojiCategory.food, ['fruit', 'stone fruit']),
  Emoji('🥭', 'mango', EmojiCategory.food, ['fruit', 'tropical']),
  Emoji('🍍', 'pineapple', EmojiCategory.food, ['fruit', 'tropical', 'pizza']),
  Emoji('🥥', 'coconut', EmojiCategory.food, ['fruit', 'tropical', 'palm']),
  Emoji('🥝', 'kiwi fruit', EmojiCategory.food, ['fruit', 'green']),
  Emoji('🍅', 'tomato', EmojiCategory.food, ['vegetable', 'salad', 'pomodoro']),
  Emoji('🥑', 'avocado', EmojiCategory.food, ['guacamole', 'toast', 'green']),
  Emoji('🥦', 'broccoli', EmojiCategory.food, [
    'vegetable',
    'green',
    'healthy',
  ]),
  Emoji('🥕', 'carrot', EmojiCategory.food, ['vegetable', 'orange']),
  Emoji('🌽', 'ear of corn', EmojiCategory.food, [
    'maize',
    'vegetable',
    'sweetcorn',
  ]),
  Emoji('🌶️', 'hot pepper', EmojiCategory.food, ['chilli', 'spicy', 'hot']),
  Emoji('🥔', 'potato', EmojiCategory.food, ['vegetable', 'spud']),
  Emoji('🍞', 'bread', EmojiCategory.food, ['loaf', 'bakery', 'toast']),
  Emoji('🥐', 'croissant', EmojiCategory.food, [
    'pastry',
    'french',
    'breakfast',
  ]),
  Emoji('🥖', 'baguette bread', EmojiCategory.food, [
    'french',
    'bakery',
    'loaf',
  ]),
  Emoji('🧀', 'cheese wedge', EmojiCategory.food, ['dairy', 'cheddar']),
  Emoji('🥚', 'egg', EmojiCategory.food, ['breakfast', 'protein']),
  Emoji('🍳', 'cooking', EmojiCategory.food, ['fried egg', 'breakfast', 'pan']),
  Emoji('🥞', 'pancakes', EmojiCategory.food, ['breakfast', 'syrup', 'stack']),
  Emoji('🥓', 'bacon', EmojiCategory.food, ['breakfast', 'pork', 'meat']),
  Emoji('🍔', 'hamburger', EmojiCategory.food, ['burger', 'fast food', 'beef']),
  Emoji('🍟', 'french fries', EmojiCategory.food, [
    'chips',
    'fast food',
    'fries',
  ]),
  Emoji('🍕', 'pizza', EmojiCategory.food, ['slice', 'italian', 'fast food']),
  Emoji('🌭', 'hot dog', EmojiCategory.food, ['sausage', 'fast food']),
  Emoji('🥪', 'sandwich', EmojiCategory.food, ['lunch', 'bread', 'sarnie']),
  Emoji('🌮', 'taco', EmojiCategory.food, ['mexican', 'lunch']),
  Emoji('🌯', 'burrito', EmojiCategory.food, ['mexican', 'wrap', 'lunch']),
  Emoji('🥗', 'green salad', EmojiCategory.food, [
    'healthy',
    'lettuce',
    'lunch',
  ]),
  Emoji('🍝', 'spaghetti', EmojiCategory.food, ['pasta', 'italian', 'noodles']),
  Emoji('🍜', 'steaming bowl', EmojiCategory.food, [
    'ramen',
    'noodles',
    'soup',
  ]),
  Emoji('🍲', 'pot of food', EmojiCategory.food, ['stew', 'soup', 'dinner']),
  Emoji('🍣', 'sushi', EmojiCategory.food, ['japanese', 'fish', 'rice']),
  Emoji('🍤', 'fried shrimp', EmojiCategory.food, [
    'tempura',
    'prawn',
    'seafood',
  ]),
  Emoji('🍚', 'cooked rice', EmojiCategory.food, ['bowl', 'asian']),
  Emoji('🍛', 'curry rice', EmojiCategory.food, ['curry', 'spicy', 'dinner']),
  Emoji('🥟', 'dumpling', EmojiCategory.food, ['gyoza', 'potsticker', 'asian']),
  Emoji('🍿', 'popcorn', EmojiCategory.food, ['cinema', 'movie', 'snack']),
  Emoji('🧂', 'salt', EmojiCategory.food, ['salty', 'seasoning', 'condiment']),
  Emoji('🍦', 'soft ice cream', EmojiCategory.food, [
    'dessert',
    'sweet',
    'cone',
  ]),
  Emoji('🍩', 'doughnut', EmojiCategory.food, ['donut', 'sweet', 'dessert']),
  Emoji('🍪', 'cookie', EmojiCategory.food, ['biscuit', 'sweet', 'snack']),
  Emoji('🎂', 'birthday cake', EmojiCategory.food, [
    'birthday',
    'celebrate',
    'candles',
  ]),
  Emoji('🍰', 'shortcake', EmojiCategory.food, ['cake', 'dessert', 'slice']),
  Emoji('🧁', 'cupcake', EmojiCategory.food, ['cake', 'dessert', 'sweet']),
  Emoji('🍫', 'chocolate bar', EmojiCategory.food, ['sweet', 'candy', 'cocoa']),
  Emoji('🍬', 'candy', EmojiCategory.food, ['sweet', 'sweets', 'treat']),
  Emoji('🍯', 'honey pot', EmojiCategory.food, ['sweet', 'bee', 'jar']),
  Emoji('☕', 'hot beverage', EmojiCategory.food, [
    'coffee',
    'tea',
    'brew',
    'morning',
  ]),
  Emoji('🫖', 'teapot', EmojiCategory.food, ['tea', 'brew', 'pot']),
  Emoji('🍵', 'teacup without handle', EmojiCategory.food, [
    'tea',
    'green tea',
    'matcha',
  ]),
  Emoji('🧃', 'beverage box', EmojiCategory.food, ['juice', 'carton', 'drink']),
  Emoji('🥤', 'cup with straw', EmojiCategory.food, [
    'soda',
    'drink',
    'takeaway',
  ]),
  Emoji('🍺', 'beer mug', EmojiCategory.food, ['beer', 'pint', 'pub', 'drink']),
  Emoji('🍻', 'clinking beer mugs', EmojiCategory.food, [
    'cheers',
    'beer',
    'toast',
  ]),
  Emoji('🥂', 'clinking glasses', EmojiCategory.food, [
    'cheers',
    'champagne',
    'celebrate',
  ]),
  Emoji('🍷', 'wine glass', EmojiCategory.food, ['wine', 'red', 'drink']),
  Emoji('🍸', 'cocktail glass', EmojiCategory.food, [
    'martini',
    'cocktail',
    'bar',
  ]),
  Emoji('🥃', 'tumbler glass', EmojiCategory.food, [
    'whisky',
    'whiskey',
    'scotch',
  ]),
  Emoji('🧊', 'ice', EmojiCategory.food, ['cube', 'cold', 'frozen']),

  // ---- Activities --------------------------------------------------------
  Emoji('⚽', 'soccer ball', EmojiCategory.activities, [
    'football',
    'sport',
    'ball',
  ]),
  Emoji('🏀', 'basketball', EmojiCategory.activities, [
    'sport',
    'ball',
    'hoop',
  ]),
  Emoji('🏈', 'american football', EmojiCategory.activities, [
    'sport',
    'nfl',
    'ball',
  ]),
  Emoji('⚾', 'baseball', EmojiCategory.activities, ['sport', 'ball', 'bat']),
  Emoji('🎾', 'tennis', EmojiCategory.activities, ['sport', 'ball', 'racket']),
  Emoji('🏐', 'volleyball', EmojiCategory.activities, [
    'sport',
    'ball',
    'beach',
  ]),
  Emoji('🏉', 'rugby football', EmojiCategory.activities, ['sport', 'ball']),
  Emoji('🎱', 'pool 8 ball', EmojiCategory.activities, [
    'billiards',
    'snooker',
    'game',
  ]),
  Emoji('🏓', 'ping pong', EmojiCategory.activities, [
    'table tennis',
    'sport',
    'paddle',
  ]),
  Emoji('🏸', 'badminton', EmojiCategory.activities, [
    'sport',
    'shuttlecock',
    'racket',
  ]),
  Emoji('🥅', 'goal net', EmojiCategory.activities, ['sport', 'goal', 'score']),
  Emoji('⛳', 'flag in hole', EmojiCategory.activities, [
    'golf',
    'sport',
    'course',
  ]),
  Emoji('🏹', 'bow and arrow', EmojiCategory.activities, [
    'archery',
    'sagittarius',
    'aim',
  ]),
  Emoji('🎣', 'fishing pole', EmojiCategory.activities, [
    'fishing',
    'rod',
    'catch',
  ]),
  Emoji('🥊', 'boxing glove', EmojiCategory.activities, [
    'boxing',
    'fight',
    'sport',
  ]),
  Emoji('🛹', 'skateboard', EmojiCategory.activities, [
    'skate',
    'board',
    'trick',
  ]),
  Emoji('🚴', 'person biking', EmojiCategory.activities, [
    'cycling',
    'bike',
    'ride',
  ]),
  Emoji('🏋️', 'person lifting weights', EmojiCategory.activities, [
    'gym',
    'weights',
    'workout',
  ]),
  Emoji('🏊', 'person swimming', EmojiCategory.activities, [
    'swim',
    'pool',
    'sport',
  ]),
  Emoji('⛷️', 'skier', EmojiCategory.activities, ['ski', 'snow', 'winter']),
  Emoji('🏂', 'snowboarder', EmojiCategory.activities, [
    'snowboard',
    'snow',
    'winter',
  ]),
  Emoji('🏆', 'trophy', EmojiCategory.activities, [
    'win',
    'award',
    'champion',
    'first',
  ]),
  Emoji('🥇', '1st place medal', EmojiCategory.activities, [
    'gold',
    'win',
    'first',
  ]),
  Emoji('🥈', '2nd place medal', EmojiCategory.activities, [
    'silver',
    'second',
  ]),
  Emoji('🥉', '3rd place medal', EmojiCategory.activities, ['bronze', 'third']),
  Emoji('🏅', 'sports medal', EmojiCategory.activities, [
    'award',
    'win',
    'medal',
  ]),
  Emoji('🎯', 'bullseye', EmojiCategory.activities, [
    'target',
    'darts',
    'goal',
    'aim',
  ]),
  Emoji('🎮', 'video game', EmojiCategory.activities, [
    'gaming',
    'controller',
    'console',
  ]),
  Emoji('🕹️', 'joystick', EmojiCategory.activities, [
    'arcade',
    'gaming',
    'retro',
  ]),
  Emoji('🎲', 'game die', EmojiCategory.activities, [
    'dice',
    'random',
    'luck',
    'board game',
  ]),
  Emoji('🧩', 'puzzle piece', EmojiCategory.activities, [
    'jigsaw',
    'solve',
    'fit',
  ]),
  Emoji('♟️', 'chess pawn', EmojiCategory.activities, [
    'chess',
    'strategy',
    'game',
  ]),
  Emoji('🎰', 'slot machine', EmojiCategory.activities, [
    'gamble',
    'casino',
    'luck',
  ]),
  Emoji('🎨', 'artist palette', EmojiCategory.activities, [
    'art',
    'paint',
    'design',
    'theme',
  ]),
  Emoji('🎬', 'clapper board', EmojiCategory.activities, [
    'film',
    'movie',
    'action',
    'cut',
  ]),
  Emoji('🎤', 'microphone', EmojiCategory.activities, [
    'sing',
    'karaoke',
    'record',
    'mic',
  ]),
  Emoji('🎧', 'headphone', EmojiCategory.activities, [
    'music',
    'listen',
    'audio',
  ]),
  Emoji('🎵', 'musical note', EmojiCategory.activities, [
    'music',
    'song',
    'tune',
  ]),
  Emoji('🎶', 'musical notes', EmojiCategory.activities, [
    'music',
    'song',
    'melody',
  ]),
  Emoji('🎸', 'guitar', EmojiCategory.activities, ['music', 'rock', 'strings']),
  Emoji('🎹', 'musical keyboard', EmojiCategory.activities, [
    'piano',
    'music',
    'keys',
  ]),
  Emoji('🥁', 'drum', EmojiCategory.activities, [
    'music',
    'beat',
    'percussion',
  ]),
  Emoji('🎺', 'trumpet', EmojiCategory.activities, ['music', 'brass', 'horn']),
  Emoji('🎻', 'violin', EmojiCategory.activities, [
    'music',
    'strings',
    'orchestra',
  ]),
  Emoji('🎉', 'party popper', EmojiCategory.activities, [
    'celebrate',
    'party',
    'hooray',
    'congrats',
  ]),
  Emoji('🎊', 'confetti ball', EmojiCategory.activities, [
    'party',
    'celebrate',
    'congrats',
  ]),
  Emoji('🎈', 'balloon', EmojiCategory.activities, [
    'party',
    'birthday',
    'celebrate',
  ]),
  Emoji('🎁', 'wrapped gift', EmojiCategory.activities, [
    'present',
    'birthday',
    'christmas',
  ]),
  Emoji('🎀', 'ribbon', EmojiCategory.activities, ['bow', 'gift', 'pretty']),
  Emoji('🎄', 'Christmas tree', EmojiCategory.activities, [
    'christmas',
    'xmas',
    'holiday',
  ]),
  Emoji('🎆', 'fireworks', EmojiCategory.activities, [
    'celebrate',
    'new year',
    'night',
  ]),
  Emoji('🪄', 'magic wand', EmojiCategory.activities, [
    'magic',
    'wizard',
    'spell',
  ]),
  Emoji('🎪', 'circus tent', EmojiCategory.activities, [
    'circus',
    'carnival',
    'show',
  ]),

  // ---- Travel & Places ---------------------------------------------------
  Emoji('🚗', 'automobile', EmojiCategory.travel, ['car', 'drive', 'vehicle']),
  Emoji('🚕', 'taxi', EmojiCategory.travel, ['cab', 'car', 'ride']),
  Emoji('🚌', 'bus', EmojiCategory.travel, ['coach', 'transport', 'commute']),
  Emoji('🚑', 'ambulance', EmojiCategory.travel, [
    'emergency',
    'medical',
    'siren',
  ]),
  Emoji('🚓', 'police car', EmojiCategory.travel, [
    'cop',
    'emergency',
    'siren',
  ]),
  Emoji('🚒', 'fire engine', EmojiCategory.travel, ['firetruck', 'emergency']),
  Emoji('🚚', 'delivery truck', EmojiCategory.travel, [
    'lorry',
    'shipping',
    'van',
  ]),
  Emoji('🚜', 'tractor', EmojiCategory.travel, ['farm', 'agriculture']),
  Emoji('🏎️', 'racing car', EmojiCategory.travel, ['f1', 'fast', 'race']),
  Emoji('🏍️', 'motorcycle', EmojiCategory.travel, [
    'motorbike',
    'ride',
    'bike',
  ]),
  Emoji('🚲', 'bicycle', EmojiCategory.travel, ['bike', 'cycle', 'ride']),
  Emoji('🛴', 'kick scooter', EmojiCategory.travel, ['scooter', 'ride']),
  Emoji('🚂', 'locomotive', EmojiCategory.travel, ['train', 'steam', 'rail']),
  Emoji('🚆', 'train', EmojiCategory.travel, ['rail', 'commute', 'transport']),
  Emoji('🚇', 'metro', EmojiCategory.travel, ['subway', 'underground', 'tube']),
  Emoji('✈️', 'airplane', EmojiCategory.travel, [
    'flight',
    'fly',
    'travel',
    'plane',
  ]),
  Emoji('🚀', 'rocket', EmojiCategory.travel, [
    'launch',
    'space',
    'ship it',
    'fast',
  ]),
  Emoji('🛸', 'flying saucer', EmojiCategory.travel, ['ufo', 'alien', 'space']),
  Emoji('🚁', 'helicopter', EmojiCategory.travel, ['chopper', 'fly', 'rotor']),
  Emoji('⛵', 'sailboat', EmojiCategory.travel, ['sail', 'yacht', 'sea']),
  Emoji('🚢', 'ship', EmojiCategory.travel, ['boat', 'cruise', 'sea']),
  Emoji('⚓', 'anchor', EmojiCategory.travel, ['ship', 'sea', 'port']),
  Emoji('🗺️', 'world map', EmojiCategory.travel, ['map', 'atlas', 'travel']),
  Emoji('🧭', 'compass', EmojiCategory.travel, [
    'navigate',
    'direction',
    'north',
  ]),
  Emoji('🏔️', 'snow-capped mountain', EmojiCategory.travel, [
    'mountain',
    'peak',
    'alps',
  ]),
  Emoji('🌋', 'volcano', EmojiCategory.travel, [
    'eruption',
    'lava',
    'mountain',
  ]),
  Emoji('🏕️', 'camping', EmojiCategory.travel, ['tent', 'outdoors', 'camp']),
  Emoji('🏖️', 'beach with umbrella', EmojiCategory.travel, [
    'beach',
    'holiday',
    'sand',
  ]),
  Emoji('🏝️', 'desert island', EmojiCategory.travel, [
    'island',
    'tropical',
    'holiday',
  ]),
  Emoji('🏠', 'house', EmojiCategory.travel, ['home', 'building', 'wfh']),
  Emoji('🏢', 'office building', EmojiCategory.travel, [
    'work',
    'office',
    'building',
  ]),
  Emoji('🏥', 'hospital', EmojiCategory.travel, [
    'medical',
    'doctor',
    'building',
  ]),
  Emoji('🏦', 'bank', EmojiCategory.travel, ['money', 'building', 'finance']),
  Emoji('🏫', 'school', EmojiCategory.travel, [
    'education',
    'building',
    'class',
  ]),
  Emoji('🏰', 'castle', EmojiCategory.travel, [
    'fortress',
    'palace',
    'medieval',
  ]),
  Emoji('🗼', 'Tokyo tower', EmojiCategory.travel, [
    'tokyo',
    'japan',
    'landmark',
  ]),
  Emoji('🗽', 'Statue of Liberty', EmojiCategory.travel, [
    'new york',
    'usa',
    'landmark',
  ]),
  Emoji('🌉', 'bridge at night', EmojiCategory.travel, [
    'bridge',
    'night',
    'city',
  ]),
  Emoji('🌃', 'night with stars', EmojiCategory.travel, [
    'city',
    'night',
    'skyline',
  ]),
  Emoji('🏙️', 'cityscape', EmojiCategory.travel, ['city', 'skyline', 'urban']),
  Emoji('🚦', 'vertical traffic light', EmojiCategory.travel, [
    'traffic',
    'stop',
    'signal',
  ]),
  Emoji('🗿', 'moai', EmojiCategory.travel, [
    'easter island',
    'statue',
    'stone',
  ]),

  // ---- Objects -----------------------------------------------------------
  Emoji('💻', 'laptop', EmojiCategory.objects, [
    'computer',
    'work',
    'code',
    'macbook',
  ]),
  Emoji('🖥️', 'desktop computer', EmojiCategory.objects, [
    'monitor',
    'pc',
    'screen',
  ]),
  Emoji('⌨️', 'keyboard', EmojiCategory.objects, ['type', 'input', 'keys']),
  Emoji('🖱️', 'computer mouse', EmojiCategory.objects, [
    'pointer',
    'click',
    'input',
  ]),
  Emoji('🖨️', 'printer', EmojiCategory.objects, ['print', 'paper', 'office']),
  Emoji('💾', 'floppy disk', EmojiCategory.objects, ['save', 'disk', 'retro']),
  Emoji('💽', 'computer disk', EmojiCategory.objects, ['minidisc', 'storage']),
  Emoji('📀', 'dvd', EmojiCategory.objects, ['disc', 'cd', 'media']),
  Emoji('📱', 'mobile phone', EmojiCategory.objects, [
    'phone',
    'smartphone',
    'iphone',
  ]),
  Emoji('☎️', 'telephone', EmojiCategory.objects, [
    'phone',
    'call',
    'landline',
  ]),
  Emoji('📞', 'telephone receiver', EmojiCategory.objects, [
    'call',
    'phone',
    'ring',
  ]),
  Emoji('📷', 'camera', EmojiCategory.objects, ['photo', 'picture', 'snap']),
  Emoji('📹', 'video camera', EmojiCategory.objects, [
    'record',
    'film',
    'video',
  ]),
  Emoji('📺', 'television', EmojiCategory.objects, ['tv', 'screen', 'watch']),
  Emoji('🔋', 'battery', EmojiCategory.objects, ['power', 'charge', 'energy']),
  Emoji('🔌', 'electric plug', EmojiCategory.objects, [
    'power',
    'socket',
    'charge',
  ]),
  Emoji('💡', 'light bulb', EmojiCategory.objects, ['idea', 'bright', 'lamp']),
  Emoji('🔦', 'flashlight', EmojiCategory.objects, [
    'torch',
    'light',
    'search',
  ]),
  Emoji('🕯️', 'candle', EmojiCategory.objects, ['light', 'flame', 'wax']),
  Emoji('🔍', 'magnifying glass tilted left', EmojiCategory.objects, [
    'search',
    'find',
    'zoom',
    'look',
  ]),
  Emoji('🔎', 'magnifying glass tilted right', EmojiCategory.objects, [
    'search',
    'find',
    'zoom',
  ]),
  Emoji('🔒', 'locked', EmojiCategory.objects, [
    'lock',
    'secure',
    'private',
    'closed',
  ]),
  Emoji('🔓', 'unlocked', EmojiCategory.objects, [
    'unlock',
    'open',
    'insecure',
  ]),
  Emoji('🔑', 'key', EmojiCategory.objects, ['unlock', 'password', 'access']),
  Emoji('🔨', 'hammer', EmojiCategory.objects, ['build', 'tool', 'fix']),
  Emoji('🪛', 'screwdriver', EmojiCategory.objects, ['tool', 'fix', 'screw']),
  Emoji('🔧', 'wrench', EmojiCategory.objects, [
    'spanner',
    'tool',
    'fix',
    'config',
  ]),
  Emoji('🔩', 'nut and bolt', EmojiCategory.objects, [
    'hardware',
    'tool',
    'fix',
  ]),
  Emoji('⚙️', 'gear', EmojiCategory.objects, [
    'settings',
    'cog',
    'config',
    'preferences',
  ]),
  Emoji('🧰', 'toolbox', EmojiCategory.objects, ['tools', 'repair', 'kit']),
  Emoji('🧲', 'magnet', EmojiCategory.objects, ['attract', 'magnetic']),
  Emoji('⚗️', 'alembic', EmojiCategory.objects, [
    'chemistry',
    'lab',
    'experiment',
  ]),
  Emoji('🔬', 'microscope', EmojiCategory.objects, [
    'science',
    'lab',
    'research',
  ]),
  Emoji('🔭', 'telescope', EmojiCategory.objects, [
    'space',
    'stars',
    'astronomy',
  ]),
  Emoji('📡', 'satellite antenna', EmojiCategory.objects, [
    'signal',
    'dish',
    'broadcast',
  ]),
  Emoji('💉', 'syringe', EmojiCategory.objects, [
    'injection',
    'vaccine',
    'medical',
  ]),
  Emoji('💊', 'pill', EmojiCategory.objects, ['medicine', 'drug', 'tablet']),
  Emoji('🚪', 'door', EmojiCategory.objects, ['entrance', 'exit', 'open']),
  Emoji('🪑', 'chair', EmojiCategory.objects, ['seat', 'furniture', 'sit']),
  Emoji('🛏️', 'bed', EmojiCategory.objects, ['sleep', 'bedroom', 'rest']),
  Emoji('🚿', 'shower', EmojiCategory.objects, ['bath', 'wash', 'clean']),
  Emoji('🧹', 'broom', EmojiCategory.objects, ['sweep', 'clean', 'tidy']),
  Emoji('🧺', 'basket', EmojiCategory.objects, ['laundry', 'picnic', 'hamper']),
  Emoji('🗑️', 'wastebasket', EmojiCategory.objects, [
    'trash',
    'bin',
    'delete',
    'rubbish',
  ]),
  Emoji('🛒', 'shopping cart', EmojiCategory.objects, [
    'trolley',
    'shop',
    'buy',
  ]),
  Emoji('💰', 'money bag', EmojiCategory.objects, ['cash', 'rich', 'salary']),
  Emoji('💵', 'dollar banknote', EmojiCategory.objects, [
    'money',
    'cash',
    'usd',
  ]),
  Emoji('💳', 'credit card', EmojiCategory.objects, ['pay', 'money', 'bank']),
  Emoji('🧾', 'receipt', EmojiCategory.objects, ['bill', 'invoice', 'expense']),
  Emoji('✉️', 'envelope', EmojiCategory.objects, ['mail', 'email', 'letter']),
  Emoji('📧', 'e-mail', EmojiCategory.objects, ['email', 'mail', 'message']),
  Emoji('📦', 'package', EmojiCategory.objects, [
    'box',
    'parcel',
    'delivery',
    'release',
  ]),
  Emoji('📋', 'clipboard', EmojiCategory.objects, [
    'copy',
    'paste',
    'notes',
    'list',
  ]),
  Emoji('📌', 'pushpin', EmojiCategory.objects, ['pin', 'note', 'attach']),
  Emoji('📎', 'paperclip', EmojiCategory.objects, ['attach', 'clip', 'file']),
  Emoji('✂️', 'scissors', EmojiCategory.objects, ['cut', 'snip', 'trim']),
  Emoji('📏', 'straight ruler', EmojiCategory.objects, [
    'measure',
    'length',
    'align',
  ]),
  Emoji('📐', 'triangular ruler', EmojiCategory.objects, [
    'measure',
    'geometry',
    'angle',
  ]),
  Emoji('📒', 'ledger', EmojiCategory.objects, [
    'notebook',
    'accounts',
    'book',
  ]),
  Emoji('📚', 'books', EmojiCategory.objects, [
    'read',
    'study',
    'library',
    'docs',
  ]),
  Emoji('📖', 'open book', EmojiCategory.objects, ['read', 'docs', 'manual']),
  Emoji('📝', 'memo', EmojiCategory.objects, ['note', 'write', 'edit', 'todo']),
  Emoji('✏️', 'pencil', EmojiCategory.objects, ['write', 'edit', 'draw']),
  Emoji('🖊️', 'pen', EmojiCategory.objects, ['write', 'sign', 'biro']),
  Emoji('🖌️', 'paintbrush', EmojiCategory.objects, ['paint', 'art', 'brush']),
  Emoji('📅', 'calendar', EmojiCategory.objects, ['date', 'schedule', 'day']),
  Emoji('📆', 'tear-off calendar', EmojiCategory.objects, [
    'date',
    'schedule',
    'deadline',
  ]),
  Emoji('⏰', 'alarm clock', EmojiCategory.objects, [
    'alarm',
    'time',
    'wake',
    'morning',
  ]),
  Emoji('⏱️', 'stopwatch', EmojiCategory.objects, ['timer', 'time', 'measure']),
  Emoji('⌛', 'hourglass done', EmojiCategory.objects, ['time', 'wait', 'sand']),
  Emoji('📊', 'bar chart', EmojiCategory.objects, [
    'graph',
    'stats',
    'data',
    'metrics',
  ]),
  Emoji('📈', 'chart increasing', EmojiCategory.objects, [
    'up',
    'growth',
    'graph',
    'improve',
  ]),
  Emoji('📉', 'chart decreasing', EmojiCategory.objects, [
    'down',
    'loss',
    'graph',
    'decline',
  ]),
  Emoji('🗂️', 'card index dividers', EmojiCategory.objects, [
    'files',
    'organise',
    'folder',
  ]),
  Emoji('📁', 'file folder', EmojiCategory.objects, [
    'folder',
    'directory',
    'files',
  ]),
  Emoji('📄', 'page facing up', EmojiCategory.objects, [
    'document',
    'file',
    'paper',
  ]),
  Emoji('🔖', 'bookmark', EmojiCategory.objects, ['save', 'tag', 'mark']),
  Emoji('🏷️', 'label', EmojiCategory.objects, ['tag', 'price', 'name']),
  Emoji('🔔', 'bell', EmojiCategory.objects, ['notification', 'alert', 'ring']),
  Emoji('🔕', 'bell with slash', EmojiCategory.objects, [
    'mute',
    'silent',
    'do not disturb',
  ]),
  Emoji('📢', 'loudspeaker', EmojiCategory.objects, [
    'announce',
    'shout',
    'broadcast',
  ]),
  Emoji('🔇', 'muted speaker', EmojiCategory.objects, [
    'mute',
    'silent',
    'quiet',
  ]),
  Emoji('🔊', 'speaker high volume', EmojiCategory.objects, [
    'loud',
    'volume',
    'sound',
  ]),
  Emoji('🎓', 'graduation cap', EmojiCategory.objects, [
    'graduate',
    'degree',
    'school',
  ]),
  Emoji('👑', 'crown', EmojiCategory.objects, [
    'king',
    'queen',
    'royal',
    'best',
  ]),
  Emoji('👓', 'glasses', EmojiCategory.objects, [
    'spectacles',
    'eyewear',
    'see',
  ]),
  Emoji('🕶️', 'sunglasses', EmojiCategory.objects, ['cool', 'shades', 'sun']),
  Emoji('👕', 't-shirt', EmojiCategory.objects, ['shirt', 'clothes', 'tee']),
  Emoji('👟', 'running shoe', EmojiCategory.objects, [
    'trainer',
    'sneaker',
    'shoe',
  ]),
  Emoji('🧢', 'billed cap', EmojiCategory.objects, ['hat', 'cap', 'baseball']),
  Emoji('☂️', 'umbrella', EmojiCategory.objects, ['rain', 'brolly', 'weather']),
  Emoji('🧳', 'luggage', EmojiCategory.objects, ['suitcase', 'travel', 'trip']),
  Emoji('🎒', 'backpack', EmojiCategory.objects, ['bag', 'school', 'rucksack']),
  Emoji('🧬', 'dna', EmojiCategory.objects, ['genetics', 'biology', 'science']),
  Emoji('🪞', 'mirror', EmojiCategory.objects, ['reflection', 'glass', 'look']),
  Emoji('🗝️', 'old key', EmojiCategory.objects, ['key', 'unlock', 'antique']),

  // ---- Symbols -----------------------------------------------------------
  Emoji('❤️', 'red heart', EmojiCategory.symbols, ['love', 'heart', 'like']),
  Emoji('🧡', 'orange heart', EmojiCategory.symbols, ['love', 'heart']),
  Emoji('💛', 'yellow heart', EmojiCategory.symbols, [
    'love',
    'heart',
    'friendship',
  ]),
  Emoji('💚', 'green heart', EmojiCategory.symbols, ['love', 'heart']),
  Emoji('💙', 'blue heart', EmojiCategory.symbols, ['love', 'heart']),
  Emoji('💜', 'purple heart', EmojiCategory.symbols, ['love', 'heart']),
  Emoji('🖤', 'black heart', EmojiCategory.symbols, ['love', 'heart', 'dark']),
  Emoji('🤍', 'white heart', EmojiCategory.symbols, ['love', 'heart', 'pure']),
  Emoji('💔', 'broken heart', EmojiCategory.symbols, [
    'sad',
    'heartbreak',
    'love',
  ]),
  Emoji('💕', 'two hearts', EmojiCategory.symbols, [
    'love',
    'hearts',
    'affection',
  ]),
  Emoji('💯', 'hundred points', EmojiCategory.symbols, [
    '100',
    'perfect',
    'score',
    'agree',
  ]),
  Emoji('💥', 'collision', EmojiCategory.symbols, [
    'boom',
    'explosion',
    'bang',
  ]),
  Emoji('💫', 'dizzy', EmojiCategory.symbols, ['stars', 'sparkle', 'spin']),
  Emoji('💤', 'zzz', EmojiCategory.symbols, ['sleep', 'tired', 'bored']),
  Emoji('✅', 'check mark button', EmojiCategory.symbols, [
    'done',
    'yes',
    'tick',
    'pass',
    'ok',
  ]),
  Emoji('☑️', 'check box with check', EmojiCategory.symbols, [
    'done',
    'tick',
    'todo',
  ]),
  Emoji('✔️', 'check mark', EmojiCategory.symbols, ['tick', 'done', 'yes']),
  Emoji('❌', 'cross mark', EmojiCategory.symbols, [
    'no',
    'wrong',
    'fail',
    'x',
    'delete',
  ]),
  Emoji('❎', 'cross mark button', EmojiCategory.symbols, ['no', 'wrong', 'x']),
  Emoji('⭕', 'hollow red circle', EmojiCategory.symbols, [
    'circle',
    'ring',
    'correct',
  ]),
  Emoji('❗', 'exclamation mark', EmojiCategory.symbols, [
    'important',
    'warning',
    'alert',
  ]),
  Emoji('❓', 'question mark', EmojiCategory.symbols, [
    'ask',
    'help',
    'unknown',
  ]),
  Emoji('⚠️', 'warning', EmojiCategory.symbols, ['caution', 'danger', 'alert']),
  Emoji('🚫', 'prohibited', EmojiCategory.symbols, [
    'no',
    'ban',
    'forbidden',
    'stop',
  ]),
  Emoji('⛔', 'no entry', EmojiCategory.symbols, [
    'stop',
    'forbidden',
    'blocked',
  ]),
  Emoji('☢️', 'radioactive', EmojiCategory.symbols, [
    'nuclear',
    'danger',
    'radiation',
  ]),
  Emoji('☣️', 'biohazard', EmojiCategory.symbols, [
    'danger',
    'toxic',
    'biological',
  ]),
  Emoji('♻️', 'recycling symbol', EmojiCategory.symbols, [
    'recycle',
    'green',
    'reuse',
  ]),
  Emoji('🔄', 'counterclockwise arrows button', EmojiCategory.symbols, [
    'refresh',
    'reload',
    'sync',
    'retry',
  ]),
  Emoji('➡️', 'right arrow', EmojiCategory.symbols, [
    'arrow',
    'right',
    'next',
    'forward',
  ]),
  Emoji('⬅️', 'left arrow', EmojiCategory.symbols, [
    'arrow',
    'left',
    'back',
    'previous',
  ]),
  Emoji('⬆️', 'up arrow', EmojiCategory.symbols, ['arrow', 'up', 'north']),
  Emoji('⬇️', 'down arrow', EmojiCategory.symbols, ['arrow', 'down', 'south']),
  Emoji('↩️', 'right arrow curving left', EmojiCategory.symbols, [
    'reply',
    'back',
    'return',
    'undo',
  ]),
  Emoji('▶️', 'play button', EmojiCategory.symbols, [
    'play',
    'start',
    'resume',
  ]),
  Emoji('⏸️', 'pause button', EmojiCategory.symbols, ['pause', 'hold', 'wait']),
  Emoji('⏹️', 'stop button', EmojiCategory.symbols, ['stop', 'end', 'halt']),
  Emoji('⏭️', 'next track button', EmojiCategory.symbols, [
    'skip',
    'next',
    'forward',
  ]),
  Emoji('🔀', 'shuffle tracks button', EmojiCategory.symbols, [
    'shuffle',
    'random',
    'mix',
  ]),
  Emoji('➕', 'plus', EmojiCategory.symbols, ['add', 'more', 'new']),
  Emoji('➖', 'minus', EmojiCategory.symbols, ['subtract', 'remove', 'less']),
  Emoji('✖️', 'multiply', EmojiCategory.symbols, [
    'times',
    'multiplication',
    'x',
  ]),
  Emoji('➗', 'divide', EmojiCategory.symbols, ['division', 'divided by']),
  Emoji('💲', 'heavy dollar sign', EmojiCategory.symbols, [
    'money',
    'dollar',
    'price',
  ]),
  Emoji('#️⃣', 'keycap: #', EmojiCategory.symbols, [
    'hash',
    'hashtag',
    'number',
    'channel',
  ]),
  Emoji('🔢', 'input numbers', EmojiCategory.symbols, [
    'numbers',
    'digits',
    '1234',
  ]),
  Emoji('🆗', 'OK button', EmojiCategory.symbols, ['ok', 'fine', 'agree']),
  Emoji('🆕', 'NEW button', EmojiCategory.symbols, ['new', 'fresh', 'latest']),
  Emoji('🆙', 'UP! button', EmojiCategory.symbols, [
    'up',
    'level up',
    'improve',
  ]),
  Emoji('🔝', 'TOP arrow', EmojiCategory.symbols, ['top', 'best', 'up']),
  Emoji('🔴', 'red circle', EmojiCategory.symbols, [
    'record',
    'dot',
    'stop',
    'error',
  ]),
  Emoji('🟠', 'orange circle', EmojiCategory.symbols, [
    'dot',
    'circle',
    'warning',
  ]),
  Emoji('🟡', 'yellow circle', EmojiCategory.symbols, [
    'dot',
    'circle',
    'pending',
  ]),
  Emoji('🟢', 'green circle', EmojiCategory.symbols, [
    'dot',
    'circle',
    'ok',
    'online',
  ]),
  Emoji('🔵', 'blue circle', EmojiCategory.symbols, ['dot', 'circle', 'info']),
  Emoji('⚪', 'white circle', EmojiCategory.symbols, ['dot', 'circle', 'empty']),
  Emoji('⚫', 'black circle', EmojiCategory.symbols, [
    'dot',
    'circle',
    'filled',
  ]),
  Emoji('🟥', 'red square', EmojiCategory.symbols, ['square', 'block', 'stop']),
  Emoji('🟩', 'green square', EmojiCategory.symbols, [
    'square',
    'block',
    'pass',
  ]),
  Emoji('🟦', 'blue square', EmojiCategory.symbols, ['square', 'block']),
  Emoji('♠️', 'spade suit', EmojiCategory.symbols, ['cards', 'poker', 'suit']),
  Emoji('♥️', 'heart suit', EmojiCategory.symbols, ['cards', 'poker', 'suit']),
  Emoji('♦️', 'diamond suit', EmojiCategory.symbols, [
    'cards',
    'poker',
    'suit',
  ]),
  Emoji('♣️', 'club suit', EmojiCategory.symbols, ['cards', 'poker', 'suit']),
  Emoji('☮️', 'peace symbol', EmojiCategory.symbols, [
    'peace',
    'hippie',
    'calm',
  ]),
  Emoji('☯️', 'yin yang', EmojiCategory.symbols, ['balance', 'tao', 'harmony']),
  Emoji('⚛️', 'atom symbol', EmojiCategory.symbols, [
    'science',
    'physics',
    'react',
  ]),
  Emoji('♾️', 'infinity', EmojiCategory.symbols, [
    'forever',
    'endless',
    'loop',
  ]),
  Emoji('™️', 'trade mark', EmojiCategory.symbols, [
    'trademark',
    'brand',
    'tm',
  ]),
  Emoji('©️', 'copyright', EmojiCategory.symbols, [
    'legal',
    'rights',
    'licence',
  ]),

  // ---- Flags -------------------------------------------------------------
  //
  // A handful of signalling flags plus a short list of national ones. National
  // flags are a set with no natural end, so the table takes the few that come up
  // as *symbols* in conversation and leaves a country picker to a picker of
  // countries.
  Emoji('🏁', 'chequered flag', EmojiCategory.flags, [
    'race',
    'finish',
    'done',
    'win',
  ]),
  Emoji('🚩', 'triangular flag', EmojiCategory.flags, [
    'red flag',
    'warning',
    'mark',
  ]),
  Emoji('🏳️', 'white flag', EmojiCategory.flags, [
    'surrender',
    'give up',
    'truce',
  ]),
  Emoji('🏴‍☠️', 'pirate flag', EmojiCategory.flags, [
    'pirate',
    'jolly roger',
    'skull',
  ]),
  Emoji('🏳️‍🌈', 'rainbow flag', EmojiCategory.flags, [
    'pride',
    'lgbt',
    'rainbow',
  ]),
  Emoji('🇬🇧', 'flag: United Kingdom', EmojiCategory.flags, [
    'uk',
    'britain',
    'gb',
    'union jack',
  ]),
  Emoji('🇺🇸', 'flag: United States', EmojiCategory.flags, [
    'usa',
    'america',
    'us',
  ]),
  Emoji('🇪🇺', 'flag: European Union', EmojiCategory.flags, ['eu', 'europe']),
  Emoji('🇨🇦', 'flag: Canada', EmojiCategory.flags, ['canada', 'ca']),
  Emoji('🇦🇺', 'flag: Australia', EmojiCategory.flags, [
    'australia',
    'au',
    'aussie',
  ]),
  Emoji('🇮🇳', 'flag: India', EmojiCategory.flags, ['india', 'in']),
  Emoji('🇩🇪', 'flag: Germany', EmojiCategory.flags, [
    'germany',
    'de',
    'deutschland',
  ]),
  Emoji('🇫🇷', 'flag: France', EmojiCategory.flags, ['france', 'fr']),
  Emoji('🇪🇸', 'flag: Spain', EmojiCategory.flags, ['spain', 'es', 'espana']),
  Emoji('🇮🇹', 'flag: Italy', EmojiCategory.flags, ['italy', 'it', 'italia']),
  Emoji('🇯🇵', 'flag: Japan', EmojiCategory.flags, ['japan', 'jp', 'nippon']),
  Emoji('🇧🇷', 'flag: Brazil', EmojiCategory.flags, [
    'brazil',
    'br',
    'brasil',
  ]),
];
