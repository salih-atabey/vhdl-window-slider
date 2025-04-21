----------------------------------------------------------------------------------
--! **Developer**: Salih Atabey
--! 
--! **Description**: This entity slides the window over the input stream and outputs the windowed data.
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity window_slider is
    generic (
        DATA_WIDTH : integer := 12;   -- Width of the data
        PAD_X      : integer := 0;    -- Width of the padding
        PAD_Y      : integer := 0;    -- Height of the padding
        WINDOW_X   : integer := 5;    -- Width of the window
        WINDOW_Y   : integer := 5;    -- Height of the window
        STRIDE_X   : integer := 1;    -- Horizontal stride
        STRIDE_Y   : integer := 1;    -- Vertical stride
        FRAME_X    : integer := 1000; -- Width of the frame
        FRAME_Y    : integer := 1000  -- Height of the frame
    );
    port (
        -- Timing
        clk : in std_logic;
        rst : in std_logic;
        -- Slave: Pixel by pixel of frame
        s_axis_tdata  : in std_logic_vector(DATA_WIDTH - 1 downto 0);
        s_axis_tready : out std_logic;
        s_axis_tvalid : in std_logic;
        -- Master: Column by column of window packet
        m_axis_tdata  : out std_logic_vector(WINDOW_Y * DATA_WIDTH - 1 downto 0);
        m_axis_tready : in std_logic;
        m_axis_tvalid : out std_logic;
        m_axis_tlast  : out std_logic
    );
end window_slider;

architecture Behavioral of window_slider is
    -- Increment X
    function increment_x(x : unsigned; y : unsigned) return unsigned is
    begin
        if x = to_unsigned(FRAME_X + 2 * PAD_X - 1, x'length) then
            return to_unsigned(0, x'length);
        else
            return x + 1;
        end if;
    end function;

    -- Increment Y
    function increment_y(x : unsigned; y : unsigned) return unsigned is
    begin
        if x = to_unsigned(FRAME_X + 2 * PAD_X - 1, x'length) then
            if y = to_unsigned(FRAME_Y + 2 * PAD_Y - 1, y'length) then
                return to_unsigned(0, y'length);
            else
                return y + 1;
            end if;
        else
            return y;
        end if;
    end function;

-- Set Buffer Start
    function set_buffer(base : std_logic_vector; data : std_logic_vector; index : integer) return std_logic_vector is
        variable base_v : std_logic_vector(WINDOW_Y * DATA_WIDTH - 1 downto 0);
    begin
        base_v := base;
        case index is
            when 0 =>
                base_v(1 * DATA_WIDTH - 1 downto 0 * DATA_WIDTH) := data;
            when 1 =>
                base_v(2 * DATA_WIDTH - 1 downto 1 * DATA_WIDTH) := data;
            when 2 =>
                base_v(3 * DATA_WIDTH - 1 downto 2 * DATA_WIDTH) := data;
            when 3 =>
                base_v(4 * DATA_WIDTH - 1 downto 3 * DATA_WIDTH) := data;
            when 4 =>
                base_v(5 * DATA_WIDTH - 1 downto 4 * DATA_WIDTH) := data;
            when others => null;
        end case;
        return base_v;
    end function;
-- Set Buffer End

-- Get Buffer Start
    function get_buffer(base : std_logic_vector; index : integer) return std_logic_vector is
    begin
        case index is
            when 0 =>
                return base(1 * DATA_WIDTH - 1 downto 0 * DATA_WIDTH);
            when 1 =>
                return base(2 * DATA_WIDTH - 1 downto 1 * DATA_WIDTH);
            when 2 =>
                return base(3 * DATA_WIDTH - 1 downto 2 * DATA_WIDTH);
            when 3 =>
                return base(4 * DATA_WIDTH - 1 downto 3 * DATA_WIDTH);
            when 4 =>
                return base(5 * DATA_WIDTH - 1 downto 4 * DATA_WIDTH);
            when others => null;
        end case;
    end function;
-- Get Buffer End

    -- State
    -- EMPTY: The memory is not fully utilized
    -- FULL: The memory is fully utilized
    -- IDLE: After reset state
    -- PAD: Padding
    -- GET: Getting the data
    -- SEND: Sending the whole window
    -- RESTORE: Restoring the data
    type state_t is (IDLE, EMPTY_PAD, EMPTY_GET, FULL_PAD_RESTORE, FULL_PAD, FULL_GET_RESTORE, FULL_GET, SEND);
    signal state      : state_t;
    signal next_state : state_t;

    -- 1D Buffer
    type memory_t is array (0 to FRAME_X + 2 * PAD_X - 1) of std_logic_vector(WINDOW_Y * DATA_WIDTH - 1 downto 0);
    signal memory : memory_t;
    -- Force BRAM inference
    attribute RAM_STYLE           : string;
    attribute RAM_STYLE of memory : signal is "block";

    -- Pointers
    signal pointer_x : unsigned(integer(ceil(log2(real(FRAME_X + 2 * PAD_X)))) - 1 downto 0);
    signal pointer_y : unsigned(integer(ceil(log2(real(FRAME_Y + 2 * PAD_Y)))) - 1 downto 0);
    signal prev_x    : unsigned(integer(ceil(log2(real(FRAME_X + 2 * PAD_X)))) - 1 downto 0);

    -- Counters
    signal stride_count_x : unsigned(integer(ceil(log2(real(STRIDE_X + 1)))) - 1 downto 0);
    signal stride_count_y : unsigned(integer(ceil(log2(real(STRIDE_Y + 1)))) - 1 downto 0);
    signal next_stride_x  : unsigned(integer(ceil(log2(real(STRIDE_X + 1)))) - 1 downto 0);
    signal next_stride_y  : unsigned(integer(ceil(log2(real(STRIDE_Y + 1)))) - 1 downto 0);
    signal restore_index  : unsigned(integer(ceil(log2(real(WINDOW_Y + 1)))) - 1 downto 0);
    signal send_index_x   : unsigned(integer(ceil(log2(real(WINDOW_X + 1)))) - 1 downto 0);

    -- Simulation
    constant MAX_COUNT_X : integer := integer(ceil(real(FRAME_X - WINDOW_X + 1) / real(STRIDE_X)));
    constant MAX_COUNT_Y : integer := integer(ceil(real(FRAME_Y - WINDOW_Y + 1) / real(STRIDE_Y)));
    signal sent_count_c  : unsigned(integer(ceil(log2(real(WINDOW_X + 1)))) - 1 downto 0);
    signal sent_count_x  : unsigned(integer(ceil(log2(real(MAX_COUNT_X + 1)))) - 1 downto 0);
    signal sent_count_y  : unsigned(integer(ceil(log2(real(MAX_COUNT_Y + 1)))) - 1 downto 0);
begin
    -- Slave ready
    s_axis_tready <= '1' when state = EMPTY_GET or state = FULL_GET else '0';

    -- Master valid
    m_axis_tvalid <= '1' when state = SEND else '0';

    -- Master data
    m_axis_tdata <= memory(to_integer(prev_x) + to_integer(send_index_x));
    m_axis_tlast <= '1' when send_index_x = to_unsigned(WINDOW_X - 1, send_index_x'length) else '0';

    -- Sent Count
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sent_count_c <= (others => '0');
                sent_count_x <= (others => '0');
                sent_count_y <= (others => '0');
            else
                if state = SEND and m_axis_tready = '1' then
                    if sent_count_c = to_unsigned(WINDOW_X - 1, sent_count_c'length) then
                        sent_count_c <= (others => '0');
                        if sent_count_x = to_unsigned(MAX_COUNT_X - 1, sent_count_x'length) then
                            sent_count_x <= (others => '0');
                            if sent_count_y = to_unsigned(MAX_COUNT_Y - 1, sent_count_y'length) then
                                sent_count_y <= (others => '0');
                            else
                                sent_count_y <= sent_count_y + 1;
                            end if;
                        else
                            sent_count_x <= sent_count_x + 1;
                        end if;
                    else
                        sent_count_c <= sent_count_c + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- State machine
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
            else
                case state is
                    when IDLE =>
                        --
                        state          <= EMPTY_PAD;
                        pointer_x      <= (others => '0');
                        pointer_y      <= (others => '0');
                        stride_count_x <= to_unsigned(STRIDE_X, stride_count_x'length);
                        stride_count_y <= to_unsigned(STRIDE_Y, stride_count_y'length);
                        restore_index  <= (others => '0');
                        send_index_x   <= (others => '0');
                        --
                    when EMPTY_PAD =>
                        --
                        if (
                            pointer_x < to_unsigned(PAD_X, pointer_x'length) or
                            pointer_x >= to_unsigned(FRAME_X + PAD_X, pointer_x'length) or
                            pointer_y < to_unsigned(PAD_Y, pointer_y'length)
                            ) then
                            memory(to_integer(pointer_x)) <= set_buffer(memory(to_integer(pointer_x)), std_logic_vector(to_unsigned(0, DATA_WIDTH)), to_integer(pointer_y));
                            --
                            pointer_x <= increment_x(pointer_x, pointer_y);
                            pointer_y <= increment_y(pointer_x, pointer_y);
                            --
                            if pointer_y >= to_unsigned(WINDOW_Y - 1, pointer_y'length) then
                                if pointer_x >= to_unsigned(FRAME_X + 2 * PAD_X - 1, pointer_x'length) then
                                    if stride_count_y >= to_unsigned(STRIDE_Y - 1, stride_count_y'length) then
                                        if stride_count_x >= to_unsigned(STRIDE_X - 1, stride_count_x'length) then
                                            state         <= SEND;
                                            next_state    <= FULL_PAD_RESTORE;
                                            next_stride_x <= to_unsigned(STRIDE_X, next_stride_x'length);
                                            next_stride_y <= (others => '0');
                                        else
                                            state          <= FULL_PAD_RESTORE;
                                            stride_count_x <= to_unsigned(STRIDE_X, stride_count_x'length);
                                            stride_count_y <= (others => '0');
                                        end if;
                                    else
                                        state          <= FULL_PAD_RESTORE;
                                        stride_count_x <= to_unsigned(STRIDE_X, stride_count_x'length);
                                        stride_count_y <= stride_count_y + 1;
                                    end if;
                                elsif pointer_x >= to_unsigned(WINDOW_X - 1, pointer_x'length) then
                                    if stride_count_y >= to_unsigned(STRIDE_Y - 1, stride_count_y'length) then
                                        if stride_count_x >= to_unsigned(STRIDE_X - 1, stride_count_x'length) then
                                            state         <= SEND;
                                            next_state    <= EMPTY_PAD;
                                            next_stride_x <= (others => '0');
                                            next_stride_y <= stride_count_y;
                                        else
                                            state          <= EMPTY_PAD;
                                            stride_count_x <= stride_count_x + 1;
                                            stride_count_y <= stride_count_y;
                                        end if;
                                    else
                                        state          <= EMPTY_PAD;
                                        stride_count_x <= stride_count_x + 1;
                                        stride_count_y <= stride_count_y;
                                    end if;
                                else
                                    state          <= EMPTY_PAD;
                                    stride_count_x <= stride_count_x;
                                    stride_count_y <= stride_count_y;
                                end if;
                            else
                                state          <= EMPTY_PAD;
                                stride_count_x <= stride_count_x;
                                stride_count_y <= stride_count_y;
                            end if;
                        else
                            if pointer_y > to_unsigned(WINDOW_Y - 1, pointer_y'length) then
                                state          <= FULL_GET_RESTORE;
                                stride_count_x <= stride_count_x;
                                stride_count_y <= stride_count_y;
                            elsif pointer_y = to_unsigned(WINDOW_Y - 1, pointer_y'length) then
                                if pointer_x >= to_unsigned(FRAME_X + 2 * PAD_X - 1, pointer_x'length) then
                                    state          <= FULL_GET_RESTORE;
                                    stride_count_x <= stride_count_x;
                                    stride_count_y <= stride_count_y;
                                elsif pointer_x >= to_unsigned(WINDOW_X - 1, pointer_x'length) then
                                    if stride_count_y >= to_unsigned(STRIDE_Y, stride_count_y'length) then
                                        if stride_count_x >= to_unsigned(STRIDE_X, stride_count_x'length) then
                                            state         <= SEND;
                                            next_state    <= EMPTY_GET;
                                            next_stride_x <= (others => '0');
                                            next_stride_y <= stride_count_y;
                                        else
                                            state          <= EMPTY_GET;
                                            stride_count_x <= stride_count_x;
                                            stride_count_y <= stride_count_y;
                                        end if;
                                    else
                                        state          <= EMPTY_GET;
                                        stride_count_x <= stride_count_x;
                                        stride_count_y <= stride_count_y;
                                    end if;
                                else
                                    state          <= EMPTY_GET;
                                    stride_count_x <= stride_count_x;
                                    stride_count_y <= stride_count_y;
                                end if;
                            else
                                state          <= EMPTY_GET;
                                stride_count_x <= stride_count_x;
                                stride_count_y <= stride_count_y;
                            end if;
                        end if;
                        --
                    when EMPTY_GET =>
                        if s_axis_tvalid = '1' then
                            memory(to_integer(pointer_x)) <= set_buffer(memory(to_integer(pointer_x)), s_axis_tdata, to_integer(pointer_y));
                            --
                            pointer_x <= increment_x(pointer_x, pointer_y);
                            pointer_y <= increment_y(pointer_x, pointer_y);
                            --
                            if pointer_y >= to_unsigned(WINDOW_Y - 1, pointer_y'length) then
                                if pointer_x >= to_unsigned(FRAME_X + PAD_X - 1, pointer_x'length) then
                                    if stride_count_y >= to_unsigned(STRIDE_Y - 1, stride_count_y'length) then
                                        if stride_count_x >= to_unsigned(STRIDE_X - 1, stride_count_x'length) then
                                            state         <= SEND;
                                            next_state    <= EMPTY_PAD;
                                            next_stride_x <= (others => '0');
                                            next_stride_y <= stride_count_y;
                                        else
                                            state          <= EMPTY_PAD;
                                            stride_count_x <= stride_count_x + 1;
                                            stride_count_y <= stride_count_y;
                                        end if;
                                    else
                                        state          <= EMPTY_PAD;
                                        stride_count_x <= stride_count_x + 1;
                                        stride_count_y <= stride_count_y;
                                    end if;
                                elsif pointer_x >= to_unsigned(WINDOW_X - 1, pointer_x'length) then
                                    if stride_count_y >= to_unsigned(STRIDE_Y - 1, stride_count_y'length) then
                                        if stride_count_x >= to_unsigned(STRIDE_X - 1, stride_count_x'length) then
                                            state         <= SEND;
                                            next_state    <= EMPTY_GET;
                                            next_stride_x <= (others => '0');
                                            next_stride_y <= stride_count_y;
                                        else
                                            state          <= EMPTY_GET;
                                            stride_count_x <= stride_count_x + 1;
                                            stride_count_y <= stride_count_y;
                                        end if;
                                    else
                                        state          <= EMPTY_GET;
                                        stride_count_x <= stride_count_x + 1;
                                        stride_count_y <= stride_count_y;
                                    end if;
                                else
                                    state          <= EMPTY_GET;
                                    stride_count_x <= stride_count_x;
                                    stride_count_y <= stride_count_y;
                                end if;
                            else
                                state          <= EMPTY_GET;
                                stride_count_x <= stride_count_x;
                                stride_count_y <= stride_count_y;
                            end if;
                        end if;
                    when FULL_PAD_RESTORE =>
                        if (
                            pointer_x < to_unsigned(PAD_X, pointer_x'length) or
                            pointer_x >= to_unsigned(FRAME_X + PAD_X, pointer_x'length) or
                            pointer_y < to_unsigned(PAD_Y, pointer_y'length) or
                            pointer_y >= to_unsigned(FRAME_Y + PAD_Y, pointer_y'length)
                            ) then
                            if restore_index < to_unsigned(WINDOW_Y - 1, restore_index'length) then
                                memory(to_integer(pointer_x)) <= set_buffer(memory(to_integer(pointer_x)), get_buffer(memory(to_integer(pointer_x)), to_integer(restore_index + 1)), to_integer(restore_index));
                                --
                                restore_index <= restore_index + 1;
                            else
                                state         <= FULL_PAD;
                                restore_index <= (others => '0');
                            end if;
                        else
                            state          <= FULL_PAD;
                            stride_count_x <= stride_count_x;
                            stride_count_y <= stride_count_y;
                        end if;
                    when FULL_PAD =>
                        --
                        if (
                            pointer_x < to_unsigned(PAD_X, pointer_x'length) or
                            pointer_x >= to_unsigned(FRAME_X + PAD_X, pointer_x'length) or
                            pointer_y < to_unsigned(PAD_Y, pointer_y'length) or
                            pointer_y >= to_unsigned(FRAME_Y + PAD_Y, pointer_y'length)
                            ) then
                            memory(to_integer(pointer_x)) <= set_buffer(memory(to_integer(pointer_x)), std_logic_vector(to_unsigned(0, DATA_WIDTH)), WINDOW_Y - 1);
                            --
                            pointer_x <= increment_x(pointer_x, pointer_y);
                            pointer_y <= increment_y(pointer_x, pointer_y);
                            --
                            if pointer_x >= to_unsigned(FRAME_X + 2 * PAD_X - 1, pointer_x'length) then
                                if pointer_y >= to_unsigned(FRAME_Y + 2 * PAD_Y - 1, pointer_y'length) then
                                    if stride_count_y >= to_unsigned(STRIDE_Y - 1, stride_count_y'length) and stride_count_x >= to_unsigned(STRIDE_X - 1, stride_count_x'length) then
                                        state      <= SEND;
                                        next_state <= IDLE;
                                    else
                                        state <= IDLE;
                                    end if;
                                else
                                    if stride_count_y >= to_unsigned(STRIDE_Y - 1, stride_count_y'length) then
                                        if stride_count_x >= to_unsigned(STRIDE_X - 1, stride_count_x'length) then
                                            state         <= SEND;
                                            next_state    <= FULL_PAD_RESTORE;
                                            next_stride_x <= to_unsigned(STRIDE_X, next_stride_x'length);
                                            next_stride_y <= (others => '0');
                                        else
                                            state          <= FULL_PAD_RESTORE;
                                            stride_count_x <= to_unsigned(STRIDE_X, stride_count_x'length);
                                            stride_count_y <= (others => '0');
                                        end if;
                                    else
                                        state          <= FULL_PAD_RESTORE;
                                        stride_count_x <= to_unsigned(STRIDE_X, stride_count_x'length);
                                        stride_count_y <= stride_count_y + 1;
                                    end if;
                                end if;
                            elsif pointer_x >= to_unsigned(WINDOW_X - 1, pointer_x'length) then
                                if stride_count_y >= to_unsigned(STRIDE_Y - 1, stride_count_y'length) then
                                    if stride_count_x >= to_unsigned(STRIDE_X - 1, stride_count_x'length) then
                                        state         <= SEND;
                                        next_state    <= FULL_PAD_RESTORE;
                                        next_stride_x <= (others => '0');
                                        next_stride_y <= stride_count_y;
                                    else
                                        state          <= FULL_PAD_RESTORE;
                                        stride_count_x <= stride_count_x + 1;
                                        stride_count_y <= stride_count_y;
                                    end if;
                                else
                                    state          <= FULL_PAD_RESTORE;
                                    stride_count_x <= stride_count_x + 1;
                                    stride_count_y <= stride_count_y;
                                end if;
                            else
                                state          <= FULL_PAD_RESTORE;
                                stride_count_x <= stride_count_x;
                                stride_count_y <= stride_count_y;
                            end if;
                        else
                            if pointer_x >= to_unsigned(FRAME_X + 2 * PAD_X - 1, pointer_x'length) then
                                if pointer_y >= to_unsigned(FRAME_Y + 2 * PAD_Y - 1, pointer_y'length) then
                                    state <= IDLE;
                                else
                                    state          <= FULL_GET_RESTORE;
                                    stride_count_x <= stride_count_x;
                                    stride_count_y <= stride_count_y;
                                end if;
                            elsif pointer_x >= to_unsigned(WINDOW_X - 1, pointer_x'length) then
                                if stride_count_y >= to_unsigned(STRIDE_Y, stride_count_y'length) then
                                    if stride_count_x >= to_unsigned(STRIDE_X, stride_count_x'length) then
                                        state         <= SEND;
                                        next_state    <= FULL_GET_RESTORE;
                                        next_stride_x <= (others => '0');
                                        next_stride_y <= stride_count_y;
                                    else
                                        state          <= FULL_GET_RESTORE;
                                        stride_count_x <= stride_count_x;
                                        stride_count_y <= stride_count_y;
                                    end if;
                                else
                                    state          <= FULL_GET_RESTORE;
                                    stride_count_x <= stride_count_x;
                                    stride_count_y <= stride_count_y;
                                end if;
                            else
                                state          <= FULL_GET_RESTORE;
                                stride_count_x <= stride_count_x;
                                stride_count_y <= stride_count_y;
                            end if;
                        end if;
                        --
                    when FULL_GET_RESTORE =>
                        if restore_index < to_unsigned(WINDOW_Y - 1, restore_index'length) then
                            memory(to_integer(pointer_x)) <= set_buffer(memory(to_integer(pointer_x)), get_buffer(memory(to_integer(pointer_x)), to_integer(restore_index + 1)), to_integer(restore_index));
                            --
                            restore_index <= restore_index + 1;
                        else
                            state         <= FULL_GET;
                            restore_index <= (others => '0');
                        end if;
                    when FULL_GET =>
                        if s_axis_tvalid = '1' then
                            memory(to_integer(pointer_x)) <= set_buffer(memory(to_integer(pointer_x)), s_axis_tdata, WINDOW_Y - 1);
                            --
                            pointer_x <= increment_x(pointer_x, pointer_y);
                            pointer_y <= increment_y(pointer_x, pointer_y);
                            --
                            if pointer_x >= to_unsigned(FRAME_X + 2 * PAD_X - 1, pointer_x'length) then
                                if pointer_y >= to_unsigned(FRAME_Y + 2 * PAD_Y - 1, pointer_y'length) then
                                    if stride_count_y >= to_unsigned(STRIDE_Y - 1, stride_count_y'length) and stride_count_x >= to_unsigned(STRIDE_X - 1, stride_count_x'length) then
                                        state      <= SEND;
                                        next_state <= IDLE;
                                    else
                                        state <= IDLE;
                                    end if;
                                else
                                    if stride_count_y >= to_unsigned(STRIDE_Y - 1, stride_count_y'length) then
                                        if stride_count_x >= to_unsigned(STRIDE_X - 1, stride_count_x'length) then
                                            state         <= SEND;
                                            next_state    <= FULL_GET_RESTORE;
                                            next_stride_x <= to_unsigned(STRIDE_X, next_stride_x'length);
                                            next_stride_y <= (others => '0');
                                        else
                                            state          <= FULL_GET_RESTORE;
                                            stride_count_x <= to_unsigned(STRIDE_X, stride_count_x'length);
                                            stride_count_y <= (others => '0');
                                        end if;
                                    else
                                        state          <= FULL_GET_RESTORE;
                                        stride_count_x <= to_unsigned(STRIDE_X, stride_count_x'length);
                                        stride_count_y <= stride_count_y + 1;
                                    end if;
                                end if;
                            elsif pointer_x >= to_unsigned(FRAME_X + PAD_X - 1, pointer_x'length) then
                                if stride_count_y >= to_unsigned(STRIDE_Y - 1, stride_count_y'length) then
                                    if stride_count_x >= to_unsigned(STRIDE_X - 1, stride_count_x'length) then
                                        state         <= SEND;
                                        next_state    <= FULL_PAD_RESTORE;
                                        next_stride_x <= (others => '0');
                                        next_stride_y <= stride_count_y;
                                    else
                                        state          <= FULL_PAD_RESTORE;
                                        stride_count_x <= stride_count_x + 1;
                                        stride_count_y <= stride_count_y;
                                    end if;
                                else
                                    state          <= FULL_PAD_RESTORE;
                                    stride_count_x <= stride_count_x + 1;
                                    stride_count_y <= stride_count_y;
                                end if;
                            elsif pointer_x >= to_unsigned(WINDOW_X - 1, pointer_x'length) then
                                if stride_count_y >= to_unsigned(STRIDE_Y - 1, stride_count_y'length) then
                                    if stride_count_x >= to_unsigned(STRIDE_X - 1, stride_count_x'length) then
                                        state         <= SEND;
                                        next_state    <= FULL_GET_RESTORE;
                                        next_stride_x <= (others => '0');
                                        next_stride_y <= stride_count_y;
                                    else
                                        state          <= FULL_GET_RESTORE;
                                        stride_count_x <= stride_count_x + 1;
                                        stride_count_y <= stride_count_y;
                                    end if;
                                else
                                    state          <= FULL_GET_RESTORE;
                                    stride_count_x <= stride_count_x + 1;
                                    stride_count_y <= stride_count_y;
                                end if;
                            else
                                state          <= FULL_GET_RESTORE;
                                stride_count_x <= stride_count_x;
                                stride_count_y <= stride_count_y;
                            end if;
                        end if;
                    when SEND =>
                        if m_axis_tready = '1' then
                            if send_index_x = to_unsigned(WINDOW_X - 1, send_index_x'length) then
                                state          <= next_state;
                                stride_count_x <= next_stride_x;
                                stride_count_y <= next_stride_y;
                                send_index_x   <= (others => '0');
                            else
                                send_index_x <= send_index_x + 1;
                            end if;
                        end if;
                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    -- Previous Process
    process (clk)
    begin
        if rising_edge(clk) then
            if pointer_x >= to_unsigned(WINDOW_X - 1, pointer_x'length) then
                if state = EMPTY_PAD or state = FULL_PAD then
                    prev_x <= pointer_x - WINDOW_X + 1;
                elsif state = EMPTY_GET or state = FULL_GET then
                    if s_axis_tvalid = '1' then
                        prev_x <= pointer_x - WINDOW_X + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end Behavioral;
