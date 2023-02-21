import { Details2Svg } from '../_shared/svg/Details2Svg';
import AddSvg from '../_shared/svg/AddSvg';
import { ICellData, IDatabaseColumn, IDatabaseRow } from '../../stores/reducers/database/slice';
import { BoardBlockItem } from './BoardBlockItem';

export const BoardBlock = ({
  title,
  groupingFieldId,
  count,
  columns,
  rows,
}: {
  title: string;
  groupingFieldId: string;
  count: number;
  columns: IDatabaseColumn[];
  rows: IDatabaseRow[];
}) => {
  return (
    <div className={'flex min-h-[250px] min-w-[250px] flex-col rounded-lg bg-surface-1'}>
      <div className={'flex items-center justify-between p-4'}>
        <div className={'flex items-center gap-2'}>
          <span>{title}</span>
          <span className={'text-shade-4'}>({count})</span>
        </div>
        <div className={'flex items-center gap-2'}>
          <button className={'h-5 w-5 rounded hover:bg-surface-2'}>
            <Details2Svg></Details2Svg>
          </button>
          <button className={'h-5 w-5 rounded hover:bg-surface-2'}>
            <AddSvg></AddSvg>
          </button>
        </div>
      </div>
      <div className={'flex-1 px-2'}>
        {rows.map((row, index) => (
          <BoardBlockItem key={index} groupingFieldId={groupingFieldId} columns={columns} row={row}></BoardBlockItem>
        ))}
      </div>
      <div className={'p-1'}>
        <button className={'flex w-full items-center gap-2 rounded-lg px-2 py-2 hover:bg-surface-2'}>
          <span className={'h-5 w-5'}>
            <AddSvg></AddSvg>
          </span>
          <span>New</span>
        </button>
      </div>
    </div>
  );
};
