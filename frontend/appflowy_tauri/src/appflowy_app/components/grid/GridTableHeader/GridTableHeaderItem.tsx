import { CellIdentifier } from '@/appflowy_app/stores/effects/database/cell/cell_bd_svc';
import { DatabaseController } from '@/appflowy_app/stores/effects/database/database_controller';
import { TypeOptionController } from '@/appflowy_app/stores/effects/database/field/type_option/type_option_controller';
import { FieldType } from '@/services/backend';
import { useState, useRef, useEffect } from 'react';
import { Some } from 'ts-results';
import { ChangeFieldTypePopup } from '../../_shared/EditRow/ChangeFieldTypePopup';
import { EditFieldPopup } from '../../_shared/EditRow/EditFieldPopup';
import { databaseActions, IDatabaseField } from '$app_reducers/database/slice';
import { FieldTypeIcon } from '$app/components/_shared/EditRow/FieldTypeIcon';
import { useResizer } from '$app/components/_shared/useResizer';
import { useAppDispatch, useAppSelector } from '$app/stores/store';
import { Details2Svg } from '$app/components/_shared/svg/Details2Svg';
import { FilterSvg } from '$app/components/_shared/svg/FilterSvg';
import { SortAscSvg } from '$app/components/_shared/svg/SortAscSvg';

const MIN_COLUMN_WIDTH = 100;

export const GridTableHeaderItem = ({
  controller,
  field,
  index,
  onShowFilterClick,
  onShowSortClick,
}: {
  controller: DatabaseController;
  field: IDatabaseField;
  index: number;
  onShowFilterClick: () => void;
  onShowSortClick: () => void;
}) => {
  const { onMouseDown, newSizeX } = useResizer((final) => {
    if (final < MIN_COLUMN_WIDTH) return;
    void controller.changeWidth({ fieldId: field.fieldId, width: final });
  });

  const filtersStore = useAppSelector((state) => state.database.filters);
  const sortStore = useAppSelector((state) => state.database.sort);

  const dispatch = useAppDispatch();
  const [showFieldEditor, setShowFieldEditor] = useState(false);
  const [editFieldTop, setEditFieldTop] = useState(0);
  const [editFieldRight, setEditFieldRight] = useState(0);

  const [showChangeFieldTypePopup, setShowChangeFieldTypePopup] = useState(false);
  const [changeFieldTypeTop, setChangeFieldTypeTop] = useState(0);
  const [changeFieldTypeRight, setChangeFieldTypeRight] = useState(0);

  const [editingField, setEditingField] = useState<IDatabaseField | null>(null);

  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!newSizeX) return;
    if (newSizeX >= MIN_COLUMN_WIDTH) {
      dispatch(databaseActions.changeWidth({ fieldId: field.fieldId, width: newSizeX }));
    }
  }, [newSizeX]);

  const changeFieldType = async (newType: FieldType) => {
    if (!editingField) return;

    const currentField = controller.fieldController.getField(editingField.fieldId);

    if (!currentField) return;

    const typeOptionController = new TypeOptionController(controller.viewId, Some(currentField));

    await typeOptionController.switchToField(newType);

    setEditingField({
      ...editingField,
      fieldType: newType,
    });

    setShowChangeFieldTypePopup(false);
  };

  const onFieldOptionsClick = () => {
    if (!ref.current) return;
    const { top, left } = ref.current.getBoundingClientRect();

    setEditFieldRight(left - 10);
    setEditFieldTop(top + 40);
    setEditingField(field);
    setShowFieldEditor(true);
  };

  return (
    <>
      <div
        style={{ width: `${field.width - (index === 0 ? 7 : 14)}px` }}
        className='flex-shrink-0 border-b border-t border-line-divider'
      >
        <div className={'flex w-full items-center justify-between py-2 pl-2'} ref={ref}>
          <div className={'flex min-w-0 items-center gap-2'}>
            <div className={'text-shade-3 flex h-5 w-5 flex-shrink-0 items-center justify-center'}>
              <FieldTypeIcon fieldType={field.fieldType}></FieldTypeIcon>
            </div>
            <span className={'text-shade-3 overflow-hidden text-ellipsis whitespace-nowrap'}>{field.title}</span>
          </div>
          <div className={'flex items-center gap-1'}>
            {sortStore.findIndex((sort) => sort.fieldId === field.fieldId) !== -1 && (
              <button onClick={onShowSortClick} className={'rounded p-1 hover:bg-fill-list-hover'}>
                <i className={'block h-[16px] w-[16px]'}>
                  <SortAscSvg></SortAscSvg>
                </i>
              </button>
            )}

            {filtersStore.findIndex((filter) => filter.fieldId === field.fieldId) !== -1 && (
              <button onClick={onShowFilterClick} className={'rounded p-1 hover:bg-fill-list-hover'}>
                <i className={'block h-[16px] w-[16px]'}>
                  <FilterSvg></FilterSvg>
                </i>
              </button>
            )}

            <button className={'rounded p-1 hover:bg-fill-list-hover'} onClick={() => onFieldOptionsClick()}>
              <i className={'block h-[16px] w-[16px]'}>
                <Details2Svg></Details2Svg>
              </i>
            </button>
          </div>
        </div>
      </div>
      <div
        className={'group h-full cursor-col-resize border-b border-t border-line-divider px-[6px]'}
        onMouseDown={(e) => onMouseDown(e, field.width)}
      >
        <div className={'flex h-full w-[3px] justify-center group-hover:bg-fill-hover'}>
          <div className={'h-full w-[1px] bg-line-divider group-hover:bg-fill-hover'}></div>
        </div>
      </div>
      {showFieldEditor && editingField && (
        <EditFieldPopup
          top={editFieldTop}
          left={editFieldRight}
          cellIdentifier={
            {
              fieldId: editingField.fieldId,
              fieldType: editingField.fieldType,
              viewId: controller.viewId,
            } as CellIdentifier
          }
          viewId={controller.viewId}
          onOutsideClick={() => {
            setShowFieldEditor(false);
          }}
          controller={controller}
          changeFieldTypeClick={(buttonTop, buttonRight) => {
            setChangeFieldTypeTop(buttonTop);
            setChangeFieldTypeRight(buttonRight);
            setShowChangeFieldTypePopup(true);
          }}
        ></EditFieldPopup>
      )}

      {showChangeFieldTypePopup && (
        <ChangeFieldTypePopup
          top={changeFieldTypeTop}
          left={changeFieldTypeRight}
          onClick={(newType) => changeFieldType(newType)}
          onOutsideClick={() => setShowChangeFieldTypePopup(false)}
        ></ChangeFieldTypePopup>
      )}
    </>
  );
};
