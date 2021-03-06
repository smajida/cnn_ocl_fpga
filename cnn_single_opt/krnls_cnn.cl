
#include "cnn_description.h"

// DATA type and shape precisions
#define DATA_TYPE float
//#define DATA_SHAPE uchar

// Helper function for relu layer after aggregation
DATA_TYPE relu(DATA_TYPE activation)
{
    return max((DATA_TYPE)0, activation);
}

// Helper function to generate index of a 2D mem block
size_t getIdx2D(const size_t y, const size_t x, const size_t width)
{
    return x + y * width;
}

// Helper function to generate index of a 3D mem block
size_t getIdx3D(const size_t z, const size_t y, const size_t x,
                            const size_t width, const size_t height)
{
    return x + y * (width) + z * (width * height);
}

// Helper function to generate index of a 4D mem block
size_t getIdx4D(const size_t d, const size_t z, const size_t y, const size_t x,
                            const size_t width, const size_t height, const size_t depth)
{
    return x + y * (width) + z * (width * height) + d * (width * height * depth);
}

// Model Parameter Sizes
#define C1_W (MASK1_SIZE * MASK1_SIZE * FEAT1_OUT)
#define C1_B (FEAT1_OUT)
#define C2_W (MASK2_SIZE * MASK2_SIZE * FEAT1_OUT * FEAT2_OUT)
#define C2_B (FEAT2_OUT)
#define D1_W (INEURON1 * ONEURON1)
#define D1_B (ONEURON1)
#define D2_W (INEURON2 * ONEURON2)
#define D2_B (ONEURON2)

// Intermediate Data Sizes
#define C1_OUT (OWIDTH1 * OHEIGHT1 * FEAT1_OUT)
#define P1_OUT (IWIDTH2 * IHEIGHT2 * FEAT1_OUT)
#define C2_OUT (OWIDTH2 * OHEIGHT2 * FEAT2_OUT)
#define P2_OUT ((OWIDTH2/2) * (OHEIGHT2/2) * FEAT2_OUT)
#define D1_OUT (ONEURON1)
#define D2_OUT (ONEURON2)

// On-Chip Constant Memory for CNN Model
global DATA_TYPE wc1[C1_W];  // CONV1 weights
global DATA_TYPE bc1[C1_B];  // CONV1 biases
global DATA_TYPE wc2[C2_W];  // CONV2 weights
global DATA_TYPE bc2[C2_B];  // CONV2 biases
global DATA_TYPE wd1[D1_W];  // FC1   weights
global DATA_TYPE bd1[D1_B];  // FC1   biases
global DATA_TYPE wd2[D2_W];  // FC2   weights
global DATA_TYPE bd2[D2_B];  // FC2   biases

// On-Chip Memory for Intermediate data between kernels
global DATA_TYPE CONV1_OUT[C1_OUT];
global DATA_TYPE CONV2_OUT[C2_OUT];
global DATA_TYPE POOL1_OUT[P1_OUT];
global DATA_TYPE POOL2_OUT[P2_OUT];
global DATA_TYPE FC1_OUT[D1_OUT];
global DATA_TYPE FC2_OUT[D2_OUT];


// A Kernel only to Move Off-Chip Constant memory to
// On-Chip Global Memory. CNN model parameters are 
// constant across different inference passes.
__kernel __attribute__((reqd_work_group_size(1,1,1)))
void load_model_ocm(__constant DATA_TYPE * conv1_w, __constant DATA_TYPE * conv1_b,
                    __constant DATA_TYPE * conv2_w, __constant DATA_TYPE * conv2_b,
                    __constant DATA_TYPE * fc1_w,   __constant DATA_TYPE * fc1_b,
                    __constant DATA_TYPE * fc2_w,   __constant DATA_TYPE * fc2_b)
{
    for(ushort i = 0; i < C1_W; ++i)
        wc1[i] = conv1_w[i];
    for(uchar i = 0; i < C1_B; ++i)
        bc1[i] = conv1_b[i];
    for(ushort i = 0; i < C2_W; ++i)
        wc2[i] = conv2_w[i];
    for(uchar i = 0; i < C2_B; ++i)
        bc2[i] = conv2_b[i];
    for(uint i = 0; i < D1_W; ++i)
        wd1[i] = fc1_w[i];
    for(ushort i = 0; i < D1_B; ++i)
        bd1[i] = fc1_b[i];
    for(ushort i = 0; i < D2_W; ++i)
        wd2[i] = fc2_w[i];
    for(uchar i = 0; i < D2_B; ++i)
        bd2[i] = fc2_b[i];
    return;
}


// Max pooling layer 1 with
// poolsize: 2x2
// stride equal to poolsize
// and 'SAME' padding policy
// 24x24 --> 12x12 
// (num of feature maps defined by 3rd dim of global work size)
//__kernel __attribute__((reqd_work_group_size(4, 4, 4)))
__kernel __attribute__((reqd_work_group_size(12, 12, 32)))
void max_pool1()
{
    size_t w = get_global_id(0);
    size_t h = get_global_id(1);
    size_t d = get_global_id(2);
    size_t idx_tl = w*2 + 24 * (h*2 + d * 24);
    size_t idx_tr = w*2 + 1 + 24 * (h*2 + d * 24);
    size_t idx_bl = w*2 + 24 * (h*2 + 1 + d * 24);
    size_t idx_br = w*2 + 1 + 24 * (h*2 + 1 + d * 24);
    size_t out_idx = w + 12 * (h + d * 12);

    __global DATA_TYPE * in = CONV1_OUT;

    POOL1_OUT[out_idx] = max(in[idx_tl], max(in[idx_tr], max(in[idx_bl], in[idx_br])));
    return;
}

// Max pooling layer 2 with
// poolsize: 2x2
// stride equal to poolsize
// and 'SAME' padding policy
// 8x8 --> 4x4 
// (num of feature maps defined by 3rd dim of global work size)
//__kernel __attribute__((reqd_work_group_size(4, 4, 4)))
__kernel __attribute__((reqd_work_group_size(4, 4, 64)))
void max_pool2()
{
    size_t w = get_global_id(0);
    size_t h = get_global_id(1);
    size_t d = get_global_id(2);
    size_t idx_tl = w*2 + 8 * (h*2 + d * 8);
    size_t idx_tr = w*2 + 1 + 8 * (h*2 + d * 8);
    size_t idx_bl = w*2 + 8 * (h*2 + 1 + d * 8);
    size_t idx_br = w*2 + 1 + 8 * (h*2 + 1 + d * 8);
    size_t out_idx = w + 4 * (h + d * 4);

    __global DATA_TYPE * in = CONV2_OUT;

    POOL2_OUT[out_idx] = max(in[idx_tl], max(in[idx_tr], max(in[idx_bl], in[idx_br])));
    return;
}

// Conv layer 1 with local memory
// kernel mask: 5x5
// stride: 1
// and 'VALID' padding policy
// 28x28x1 --> 24x24x32
#define CONV1_WG_X  24
#define CONV1_WG_Y  24
#define CONV1_WG_Z  1
#define TILE1_X (CONV1_WG_X+MASK1_SIZE-1)
#define TILE1_Y (CONV1_WG_Y+MASK1_SIZE-1)
#define TILE1_Z MASK1_DEPTH

__kernel __attribute__((reqd_work_group_size(CONV1_WG_X, CONV1_WG_Y, CONV1_WG_Z)))
void conv1(__global DATA_TYPE * in)
{
    __local DATA_TYPE tile[TILE1_X * TILE1_Y * TILE1_Z]
        __attribute__((xcl_array_partition(cyclic,5,1)));
    __local DATA_TYPE w_cache[MASK1_SIZE * MASK1_SIZE * MASK1_DEPTH]
        __attribute__((xcl_array_partition(cyclic,5,1)));

    size_t w = get_global_id(0);
    size_t h = get_global_id(1);
    size_t d = get_global_id(2);

    async_work_group_copy(&tile[0], &in[0], (TILE1_X * TILE1_Y * TILE1_Z), 0);
    
    ushort w_idx = d * MASK1_SIZE * MASK1_SIZE * MASK1_DEPTH;
    async_work_group_copy(&w_cache[0], &wc1[w_idx], MASK1_SIZE * MASK1_SIZE * MASK1_DEPTH, 0);

    DATA_TYPE c = (DATA_TYPE)0;
    for(size_t cd = 0; cd < MASK1_DEPTH; ++cd)
    {
        __attribute__((opencl_unroll_hint))
        for(size_t ch = 0; ch < MASK1_SIZE; ++ch)
        {
            __attribute__((opencl_unroll_hint))
            for(size_t cw = 0; cw < MASK1_SIZE; ++cw)
            {
                c += tile[getIdx3D(cd, ch + h, cw + w, TILE1_X, TILE1_Y)]
                    * w_cache[getIdx3D(cd, ch, cw, MASK1_SIZE, MASK1_SIZE)];
            }
        }
    }

    size_t out_idx = w + OWIDTH1 * (h + OHEIGHT1 * d);
    CONV1_OUT[out_idx] = relu(c + bc1[d]);
    return;
}

// Conv layer 2 with local memory
// kernel mask: 5x5
// stride: 1
// and 'VALID' padding policy
// 12x12x32 --> 8x8x64
#define CONV2_WG_X  8
#define CONV2_WG_Y  8
//#define CONV2_WG_Z  8
#define CONV2_WG_Z  16
#define TILE2_X (CONV2_WG_X+MASK2_SIZE-1)
#define TILE2_Y (CONV2_WG_Y+MASK2_SIZE-1)
#define TILE2_Z MASK2_DEPTH

__kernel __attribute__((reqd_work_group_size(CONV2_WG_X, CONV2_WG_Y, CONV2_WG_Z)))
void conv2()
{
    __global DATA_TYPE * in = POOL1_OUT;

    __local DATA_TYPE tile[TILE2_X * TILE2_Y * TILE2_Z];
//        __attribute__((xcl_array_partition(cyclic,25,1)));
    __local DATA_TYPE w_cache[MASK2_SIZE * MASK2_SIZE * MASK2_DEPTH * CONV2_WG_Z]
        __attribute__((xcl_array_partition(cyclic,5,1)));
    __local DATA_TYPE b_cache[CONV2_WG_Z];

    __private DATA_TYPE acc_cache[MASK2_SIZE * MASK2_SIZE];
    uchar w = get_global_id(0);
    uchar h = get_global_id(1);
    uchar d = get_global_id(2);
    uchar g_id = get_group_id(2);
    uchar l_id = get_local_id(2);

    size_t out_idx = 0;
    __attribute__((xcl_pipeline_workitems))
    {
    ushort w_idx = g_id * MASK2_SIZE * MASK2_SIZE * MASK2_DEPTH * CONV2_WG_Z;
    ushort b_idx = g_id * CONV2_WG_Z;
    
    async_work_group_copy(&tile[0], &in[0], TILE2_X * TILE2_Y * TILE2_Z, 0);
    async_work_group_copy(&w_cache[0], &wc2[w_idx], MASK2_SIZE * MASK2_SIZE * MASK2_DEPTH * CONV2_WG_Z, 0);
    async_work_group_copy(&b_cache[0], &bc2[b_idx], CONV2_WG_Z, 0);

    __attribute__((opencl_unroll_hint))
    for(ushort i = 0; i < MASK2_SIZE * MASK2_SIZE; ++i)
        acc_cache[i] = (DATA_TYPE)0;

    out_idx = w + OWIDTH2 * (h + OHEIGHT2 * d);
    }

    DATA_TYPE c = (DATA_TYPE)0;
    __attribute__((xcl_pipeline_loop))
    for(size_t cd = 0; cd < MASK2_DEPTH; ++cd)
    {
        __attribute__((opencl_unroll_hint))
        for(size_t ch = 0; ch < MASK2_SIZE; ++ch)
        {
            __attribute__((opencl_unroll_hint))
            for(size_t cw = 0; cw < MASK2_SIZE; ++cw)
            {
                ushort idx = getIdx2D(ch, cw, MASK2_SIZE);
                acc_cache[idx] += tile[getIdx3D(cd, ch+h, cw+w, TILE2_X, TILE2_Y)]
                 *  w_cache[idx + (cd + l_id * MASK2_DEPTH) * MASK2_SIZE * MASK2_SIZE];
            }
        }
    }

    __attribute__((xcl_pipeline_workitems))
    {
        __attribute__((opencl_unroll_hint))
        for(ushort i = 0; i < MASK2_SIZE * MASK2_SIZE; ++i)
        {
            c += acc_cache[i];
        }
    
        //CONV2_OUT[out_idx] = relu(c + bc2[d]);
        CONV2_OUT[out_idx] = relu(c + b_cache[l_id]);
    }
    return;
}

// Fully connected layer
// kernel launch grid based on
// number of output neuron
#define FC1_WG_NUM 4   // Number of work-groups is 2
#define ACC_CACHE_SIZE (INEURON1 / 64)
__kernel __attribute__((reqd_work_group_size((ONEURON1/FC1_WG_NUM), 1, 1)))
void fc1()
{
    __global DATA_TYPE * in = POOL2_OUT;
    __global DATA_TYPE * out = FC1_OUT;

    __local DATA_TYPE in_cache[P2_OUT];
    __private DATA_TYPE acc_cache[ACC_CACHE_SIZE];

    __attribute__((xcl_pipeline_workitems))
    {
        __attribute__((opencl_unroll_hint))
        for(ushort i = 0; i < ACC_CACHE_SIZE; ++i)
            acc_cache[i] = (DATA_TYPE)0;
    }

    async_work_group_copy(&in_cache[0], &in[0], P2_OUT, 0);

    //DATA_TYPE n = 0;
    size_t neuron = get_global_id(0);
    __attribute__((xcl_pipeline_loop))
    for(size_t c = 0; c < INEURON1; ++c)
    {
        //n += in[c] * wd1[neuron * INEURON1 + c];
        acc_cache[c % ACC_CACHE_SIZE] += in_cache[c] * wd1[neuron * INEURON1 + c];
    }

    __attribute__((xcl_pipeline_workitems))
    {
        DATA_TYPE n = 0;
        __attribute__((opencl_unroll_hint))
        for(ushort i = 0; i < ACC_CACHE_SIZE; ++i)
            n += acc_cache[i];
        out[neuron] = relu(n + bd1[neuron]);
    }
    return;
}

#define FC2_WG_NUM 2    // Number of work-groups is 2
__kernel __attribute__((reqd_work_group_size((ONEURON2/FC2_WG_NUM), 1, 1)))
void fc2()
{
    __global DATA_TYPE * in = FC1_OUT;
    __global DATA_TYPE * out = FC2_OUT;

    size_t neuron = get_global_id(0);
    DATA_TYPE n = 0;
    __attribute__((xcl_pipeline_loop))
    for(size_t c = 0; c < INEURON2; ++c)
    {
        n += in[c] * wd2[neuron * INEURON2 + c];
    }
    out[neuron] = relu(n + bd2[neuron]);
    return;
}

__kernel  __attribute__((reqd_work_group_size(1, 1, 1)))
void softmax_layer(__global DATA_TYPE * out)
{
    __global DATA_TYPE * in = FC2_OUT;

    DATA_TYPE soft[10];
    DATA_TYPE sum_exp = 0;
    __attribute__((xcl_pipeline_loop))
    for(uchar i = 0; i < 10; ++i)
    {
        soft[i] = native_exp(in[i]);
        sum_exp += soft[i];
    }

    __attribute__((xcl_pipeline_loop))
    for(uchar i = 0; i < 10; ++i)
    {
        out[i] = soft[i] / sum_exp;
    }
    return;
}

