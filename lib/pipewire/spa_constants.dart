/// SPA constants transcribed from the PipeWire headers (spa/utils/type.h,
/// spa/param/*.h, pipewire/stream.h). Only what the video-source stream path
/// uses.
library;

// --- Pod types (spa/utils/type.h) ---
const int spaTypeNone = 1;
const int spaTypeBool = 2;
const int spaTypeId = 3;
const int spaTypeInt = 4;
const int spaTypeLong = 5;
const int spaTypeFloat = 6;
const int spaTypeDouble = 7;
const int spaTypeString = 8;
const int spaTypeRectangle = 10;
const int spaTypeFraction = 11;
const int spaTypeArray = 13;
const int spaTypeStruct = 14;
const int spaTypeObject = 15;
const int spaTypeChoice = 19;

// --- Object types ---
const int spaTypeObjectFormat = 0x40003;
const int spaTypeObjectParamBuffers = 0x40004;

// --- Choice types (spa/utils/type.h enum spa_choice_type) ---
const int spaChoiceNone = 0;
const int spaChoiceRange = 1;
const int spaChoiceStep = 2;
const int spaChoiceEnum = 3;
const int spaChoiceFlags = 4;

// --- Param ids (spa/param/param.h) ---
const int spaParamEnumFormat = 3;
const int spaParamFormat = 4;
const int spaParamBuffers = 5;

// --- Format object keys (spa/param/format.h) ---
const int spaFormatMediaType = 1;
const int spaFormatMediaSubtype = 2;
const int spaFormatVideoFormat = 0x20001;
const int spaFormatVideoSize = 0x20003;
const int spaFormatVideoFramerate = 0x20004;
const int spaFormatVideoMaxFramerate = 0x20005;

const int spaMediaTypeVideo = 2;
const int spaMediaSubtypeRaw = 1;

// --- Video formats (spa/param/video/raw.h) ---
const int spaVideoFormatRGBx = 7;
const int spaVideoFormatBGRx = 8;
const int spaVideoFormatRGBA = 11;
const int spaVideoFormatBGRA = 12;

// --- Buffers object keys (spa/param/buffers.h) ---
const int spaParamBuffersBuffers = 1;
const int spaParamBuffersBlocks = 2;
const int spaParamBuffersSize = 3;
const int spaParamBuffersStride = 4;
const int spaParamBuffersAlign = 5;
const int spaParamBuffersDataType = 6;

// --- Data types (spa/buffer/buffer.h) ---
const int spaDataMemFd = 2;

// --- pw_stream (pipewire/stream.h) ---
const int pwDirectionOutput = 1;
const int pwIdAny = 0xffffffff;

const int pwStreamFlagMapBuffers = 1 << 2;
const int pwStreamFlagDriver = 1 << 3;

const int pwStreamStateError = -1;
const int pwStreamStateUnconnected = 0;
const int pwStreamStateConnecting = 1;
const int pwStreamStatePaused = 2;
const int pwStreamStateStreaming = 3;

const int pwVersionStreamEvents = 2;
