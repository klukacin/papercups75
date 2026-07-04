// antd's DatePicker is dayjs-based by default (since antd 5), so we can just
// re-export it directly. (Previously this used rc-picker's generatePicker to
// swap moment for dayjs, which is no longer necessary — and antd 6 removed
// those internal entry points.)
import {DatePicker} from 'antd';

export default DatePicker;
